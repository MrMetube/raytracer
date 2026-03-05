#+vet unused shadowing cast unused-imports style unused-variables unused-procedures
package build

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:terminal/ansi"
import "../code/shared" // Get the shared format string iterator. Ughh...

Info :: struct { 
    name: string, 
    type: string, 
    location: tokenizer.Pos,
}

Printlike :: struct {
    name:         string,
    format_index: int, 
    args_index:   int,
}

Procedure :: struct {
    name:         string,
    return_count: int,
}

File :: struct {
    file_name: string,
    infos: [dynamic] Info,
}

Metaprogram :: struct {
    files: map[string] string,
    
    collections: map[string] Collector,
    
    commons: map[string][dynamic] File,
    exports: map[string][dynamic] Info,
    
    apis: [dynamic] File,
    
    // @note(viktor): we assume that noone will make a local rename onto a name specified in another scope, scopes are ignored
    printlikes: map[string] Printlike,
    procedures: map[string] Procedure,
    printlikes_failed: bool,
}

Collector :: struct {
    entries: [dynamic] Collector_Entry,
    stack:   [dynamic] int,
}

Collector_Entry :: struct {
    node: ^ast.Node,
    next: int,
}

metaprogram_collect_files_and_parse_package :: proc (mp: ^Metaprogram, directory, package_name: string) -> (success: bool) {
    fi, err := os.read_directory_by_path(directory, -1, context.allocator)
    if err != nil {
        fmt.eprintfln("ERROR: The metaprogram failed to read the package %v", directory)
        return false
    }
    
    for f in fi {
        bytes, _ := os.read_entire_file_from_path(f.fullpath, context.allocator)
        absolute_path, _ := os.get_absolute_path(f.fullpath, context.allocator)
        mp.files[absolute_path] = cast(string) bytes
    }
    
    pack, ok := parser.parse_package_from_path(directory)
    if !ok {
        fmt.eprintfln("ERROR: The metaprogram failed to parse the package %v", directory)
        return false
    }
    
    collector: Collector
    
    v := ast.Visitor{ visit = proc (visitor: ^ast.Visitor, node: ^ast.Node) -> (^ast.Visitor) {
        s  := cast(^Collector) visitor.data
        if node != nil {
            idx := len(s.entries)
            append(&s.entries, Collector_Entry{ node = node, next = -1 })
            append(&s.stack, idx)
            return visitor
        } else {
            // nil node means we are done with the children of the last node
            idx := pop(&s.stack)
            s.entries[idx].next = len(s.entries)
            return nil
        }
        
        return visitor
    }, data = &collector }
    
    ast.walk(&v, pack)
    mp.collections[package_name] = collector
    
    return true
}

////////////////////////////////////////////////

check_printlikes :: proc (mp: ^Metaprogram, package_name: string) -> (success: bool) {
    collector, cok := mp.collections[package_name]
    if !cok do return false
    
    for index: int; index < len(collector.entries); {
        skip_children: bool
        node := collector.entries[index]
        
        if call, ok := node.node.derived.(^ast.Call_Expr); ok {
            check_printlike_call(mp, call)
        }
        
        index = skip_children ? node.next : index+1
    }
    
    return !mp.printlikes_failed
}

////////////////////////////////////////////////

union_contains :: proc (value: $U, $T: typeid) -> bool {
    _, ok := value.(T)
    return ok
}

check_printlike_call :: proc (mp: ^Metaprogram, call: ^ast.Call_Expr) {
    proc_ident: ^ast.Ident
    if ident, iok := call.expr.derived_expr.(^ast.Ident); iok {
        proc_ident = ident
    } else if selector, sok := call.expr.derived_expr.(^ast.Selector_Expr); sok {
        proc_ident = selector.field
    } else if union_contains(call.expr.derived_expr, ^ast.Basic_Directive) || union_contains(call.expr.derived_expr, ^ast.Paren_Expr) || union_contains(call.expr.derived_expr, ^ast.Inline_Asm_Expr) {
        return
    } else {
        fmt.println(call)
        unimplemented()
    }
    
    name := proc_ident.name
    printlike, ok := mp.printlikes[name]
    if !ok do return
    
    assert(printlike.format_index <= len(call.args))
    format_arg := call.args[printlike.format_index]
    
    format: string
    if format_field_value, set_format_by_name := format_arg.derived_expr.(^ast.Field_Value); set_format_by_name {
        format_value := ast.unparen_expr(format_field_value.value)
        if lit, lok := format_value.derived_expr.(^ast.Basic_Lit); lok {
            if lit.tok.kind == .String {
                format = lit.tok.text
            } else {
                // @incomplete not handling any other kind or nested expression
            }
        } else {
            // @incomplete Not handling non-literal asignments
        }
    } else {
        format = read_pos(mp, format_arg.pos, format_arg.end)
    }
    
    if format == "" do return
    
    format_string_ok, expected := get_expected_format_string_arg_count(format)
    
    the_actual_arg_count_is_unknown := false
    the_actual_arg_count_is_unknown_because: string
    
    actual: int
    if format_string_ok {
        if printlike.args_index >= len(call.args) {
            // @note(viktor): no args where passed
            actual = 0
        } else {
            args := call.args[printlike.args_index]
            if arg_field_value, set_args_by_name := args.derived_expr.(^ast.Field_Value); set_args_by_name {
                fmt.printfln("%v:%v:%v", args.pos.file, args.pos.line, args.pos.column)
                arg_value := ast.unparen_expr(arg_field_value.value)
                if !union_contains(arg_value.derived_expr, ^ast.Ident) {
                    // @todo(viktor): if it is an array literal we can still check it
                } else {
                    the_actual_arg_count_is_unknown = true
                    the_actual_arg_count_is_unknown_because = "Cannot check the value of the variable assigned to the args parameter."
                }
            } else {
                outer: for arg in call.args[printlike.args_index:] {
                    if union_contains(arg.derived_expr, ^ast.Field_Value) do continue
                    
                    handled: b32
                    // @todo(viktor): some other expressions like ternary expressions could also yield more than one arg, but that would require a recursive approach
                    arg := arg
                    arg = ast.unparen_expr(arg)
                    #partial switch value in arg.derived_expr {
                    case ^ast.Call_Expr:
                        expr_name := value.expr.derived_expr.(^ast.Ident).name
                        if procedure, proc_ok := mp.procedures[expr_name]; proc_ok {
                            actual += procedure.return_count
                            handled = true
                        } else {
                            // @incomplete if the name is a proc group we dont know which of the procs is called, thanks bill..
                            the_actual_arg_count_is_unknown = true
                            the_actual_arg_count_is_unknown_because = "The args contain at least one call to a proc-groups."
                        }
                    }
                    
                    if !handled do actual += 1
                }
            }
        }
    }
    
    if the_actual_arg_count_is_unknown {
        report_unchecked_printlike_call(mp, call, expected, the_actual_arg_count_is_unknown_because)
    } else {
        if expected != actual {
            report_printlike_error(mp, call, expected, actual)
        }
    }
}

////////////////////////////////////////////////

report_printlike_error :: proc (mp: ^Metaprogram, call: ^ast.Call_Expr, expected, actual: int) {
    mp.printlikes_failed = true
    
    fmt.eprintf("%v%v:%v:%v: ", White, call.pos.file, call.pos.line, call.pos.column)
    fmt.eprintf("%vFormat Error: %v", Red, Reset)
    if expected == 0 {
        fmt.eprintf("There are no formating percent signs in the format string")
    } else if expected == 1 {
        fmt.eprintf("There is one formating percent sign in the format string")
    } else { 
        fmt.eprintf("There are %v formating percent signs in the format string", expected)
    }
    if actual == 0 {
        fmt.eprintf(", but you passed no arguments.\n")
    } else if actual == 1 {
        fmt.eprintf(", but you passed one argument.\n")
    } else { 
        fmt.eprintf(", but you passed %v arguments.\n", actual)
    }

    fmt.eprintf("\t%v", White)
    
    full_call := read_pos(mp, call.pos, call.end)
    report_highlight_percent_signs(full_call, expected)
}

report_unchecked_printlike_call :: proc (mp: ^Metaprogram, call: ^ast.Call_Expr, expected: int, excuse: string) {
    fmt.eprintf("%v%v:%v:%v: ", White, call.pos.file, call.pos.line, call.pos.column)
    fmt.eprintf("%vFormat Warning: %v", Yellow, Reset)
    fmt.eprintf("%v %v\n", "Unable to check the arguments count.", excuse)
    
    fmt.eprintf("\t%v", White)
    
    full_call := read_pos(mp, call.pos, call.end)
    report_highlight_percent_signs(full_call, expected)
}

report_highlight_percent_signs :: proc (full_call: string, expected: int) {
    escaped: int
    
    iter := shared.make_format_iterator(full_call)
    for part in shared.iterate_format(&iter) {
        if part.kind == .Percent {
            fmt.eprintf("%v%v%v", Blue, part.text, White)
        } else if part.kind == .Escaped {
            fmt.eprintf("%v%v%v", Yellow, part.text, White)
            escaped += 1
        } else {
            fmt.eprintf("%v", part.text)
        }
    }
    
    fmt.eprintfln("%v", Reset)
    
    if expected > 0 do fmt.eprintf("\t%v%v%v indicates a formatting percent sign.\n", Blue, "%",  Reset)
    if escaped  > 0 do fmt.eprintf("\t%v%v%v indicates an escaped percent sign.\n", Yellow, "%%", Reset)
    
    fmt.eprintf("\n")
}

get_expected_format_string_arg_count :: proc (format: string) -> (ok: bool, count: int) {
    if format[0] == '"' || format[0] == '`' {
        ok = true
        
        iter := shared.make_format_iterator(format)
        for element in shared.iterate_format(&iter) {
            if element.kind == .Percent {
                count += 1
            }
        }
    }
    
    return ok, count
}

////////////////////////////////////////////////

White  :: ansi.CSI + ansi.FG_BRIGHT_WHITE  + ansi.SGR
Red    :: ansi.CSI + ansi.FG_BRIGHT_RED    + ansi.SGR
Yellow :: ansi.CSI + ansi.FG_BRIGHT_YELLOW + ansi.SGR
Blue   :: ansi.CSI + ansi.FG_BRIGHT_BLUE   + ansi.SGR
Green  :: ansi.CSI + ansi.FG_BRIGHT_GREEN  + ansi.SGR
Reset  :: ansi.CSI + ansi.FG_DEFAULT       + ansi.SGR

has_attribute :: proc { has_attribute_import, has_attribute_value, has_attribute_raw }
has_attribute_import :: proc (Import: ^ast.Import_Decl, target: string, target_value := "") -> (result: bool) {
    return has_attribute(Import.attributes[:], target, target_value)
}
has_attribute_value :: proc (value: ^ast.Value_Decl, target: string, target_value := "") -> (result: bool) {
    return has_attribute(value.attributes[:], target, target_value)
}
has_attribute_raw :: proc (attributes: [] ^ast.Attribute, target: string, target_value := "") -> (result: bool) {
    loop: for attribute in attributes {
        for elem in attribute.elems {
            name: string
            value: string
            if field_value, fok := elem.derived_expr.(^ast.Field_Value); fok {
                name = field_value.field.derived_expr.(^ast.Ident).name
                
                if lit, lok := field_value.value.derived_expr.(^ast.Basic_Lit); lok {
                    value = lit.tok.text
                }
            } else {
                name = elem.derived_expr.(^ast.Ident).name
            }
            
            if target == name {
                if target_value == "" || target_value == value {
                    result = true
                }
                
                break loop
            }
        }
    }
    
    return result
}

read_pos :: proc (mp: ^Metaprogram, start, end: tokenizer.Pos) -> (result: string) {
    if start.file != end.file {
        fmt.eprintln("bad pos pair:", start, end)
        assert(false)
    }
    
    file, ok := mp.files[start.file]
    
    if !ok {
        fmt.eprintln("unknown file:", start.file)
        assert(false)
    }
    
    result = file[start.offset:end.offset]
    return result
}