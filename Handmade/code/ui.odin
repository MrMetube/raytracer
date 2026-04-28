package main

import "base:intrinsics"
import "core:math"
import rl "vendor:raylib"

UI :: struct {
    ended_interaction:    Interaction, // @naming
    active_interaction:   Interaction,
    hot_interaction:      Interaction,
    next_hot_interaction: Interaction,
    
    mouse_p:  v2,
    mouse_dp: v2,
}

Interaction :: struct {
    kind: Interaction_Kind,
    target: pmm,
    
    right, middle: bool,
    
    value:  union {
        string,
        bool,
        u32,
        i32,
        f32,
        int,
        Object_Id,
        Material_Id,
        Debug_View_Kind,
    },
}

Interaction_Kind :: enum {
    None,
    NOP,
    SetValue,
    Drag,
    Move,
    Select,
}

DraggerFlag :: enum {
    logarithmic,
}
DraggerFlags :: bit_set[DraggerFlag]

Theme :: struct {
    outline: v4,
    background: v4,
    text: v4,
    text_shadow: v4,
}

////////////////////////////////////////////////

begin_ui :: proc (ui: ^UI) {
    ui.mouse_p  = rl.GetMousePosition()
    ui.mouse_dp = rl.GetMouseDelta()
}


interact :: proc (ui: ^UI) {
    // @todo(viktor): set cursor based on active.interaction
    // if none are active based on hot_interaction
    ui.ended_interaction = {}
    
    if ui.active_interaction.kind != .None {
        switch ui.active_interaction.kind {
        case .None: unreachable()
        case .NOP, .SetValue, .Select, .Move: // @note(viktor): nothing
        case .Drag:
            width  := cast(f32) rl.GetScreenWidth()
            height := cast(f32) rl.GetScreenHeight()
            
            wrapped := false
            
            new_p := ui.mouse_p
            if ui.mouse_p.x <= 0 {
                new_p.x = width - 2
                wrapped = true
            } else if ui.mouse_p.x >= width - 1 {
                new_p.x = 1
                wrapped = true
            }
            
            if ui.mouse_p.y <= 0 {
                new_p.y = height - 2
                wrapped = true
            } else if ui.mouse_p.y >= height - 1 {
                new_p.y = 1
                wrapped = true
            }
            
            if wrapped {
                rl.SetMousePosition(cast(i32) new_p.x, cast(i32) new_p.y)
                ui.mouse_dp = {0, 0}
            }
        }
        
        if is_interacting_release(ui) do end_interaction(ui)
        if is_interacting_press(ui)   do begin_interaction(ui)
    } else {
        ui.hot_interaction = ui.next_hot_interaction
        if is_interacting_press(ui)   do begin_interaction(ui)
        if is_interacting_release(ui) do end_interaction(ui)
    }
    
    ui.next_hot_interaction = {}
}

begin_interaction :: proc (ui: ^UI) {
    if ui.hot_interaction.kind != .None {
        ui.active_interaction = ui.hot_interaction
    } else {
        ui.active_interaction.kind = .NOP
    }
}

end_interaction :: proc (ui: ^UI) {
    action := &ui.active_interaction
    switch action.kind {
    case .None: unreachable()
    case .NOP:  // nothing
    case .SetValue, .Drag, .Select, .Move:
        ui.ended_interaction = action^
    }
    
    action^ = {}
}

is_interacting_press :: proc (ui: ^UI) -> bool {
    it := ui.active_interaction
    if ui.active_interaction.kind == .None {
        it = ui.hot_interaction
    }
    
    result: bool
    result ||= rl.IsMouseButtonPressed(.LEFT)
    if it.middle do result ||= rl.IsMouseButtonPressed(.MIDDLE)
    if it.right  do result ||= rl.IsMouseButtonPressed(.RIGHT)
    
    return result
}

is_interacting_release :: proc (ui: ^UI) -> bool {
    it := ui.active_interaction
    if ui.active_interaction.kind == .None {
        it = ui.hot_interaction
    }
    
    result: bool
    result ||= rl.IsMouseButtonReleased(.LEFT)
    if it.middle do result ||= rl.IsMouseButtonReleased(.MIDDLE)
    if it.right  do result ||= rl.IsMouseButtonReleased(.RIGHT)
    
    return result
}

////////////////////////////////////////////////

is_hot :: proc (ui: ^UI, interaction: Interaction) -> bool {
    result := ui.hot_interaction == interaction
    return result
}

is_active :: proc (ui: ^UI, interaction: Interaction) -> bool {
    result := ui.active_interaction == interaction
    return result
}

// @naming
is_ended :: proc (ui: ^UI, interaction: Interaction) -> bool {
    result := ui.ended_interaction == interaction
    return result
}

////////////////////////////////////////////////

set_value_interaction :: proc (target: ^$T, value: T) -> Interaction {
    result: Interaction
    result.kind = .SetValue
    result.target = target
    result.value  = value
    return result
}

////////////////////////////////////////////////

// @cleanup what is an interaction in this once we have drags and sliders and moves
ui_button :: proc (parent: ^UI_Element, interaction: Interaction, format: string, args: ..any) -> bool {
    hot    := is_hot(parent.ui, interaction)
    active := is_active(parent.ui, interaction)
    
    theme := theme_button(hot, active)
    result := ui_themed_button(parent, interaction, theme, format, ..args)
    
    return result
}

ui_toggle :: proc (parent: ^UI_Element, condition: ^bool, format: string, args: ..any) -> bool {
    interaction := set_value_interaction(condition, !condition^)
    hot    := is_hot(parent.ui, interaction)
    active := is_active(parent.ui, interaction) || condition^
    
    theme := theme_button(hot, active)
    clicked := ui_themed_button(parent, interaction, theme, format, ..args)
    
    if clicked {
        condition^ = !condition^
    }
    
    return clicked
}

ui_collapser :: proc (parent: ^UI_Element, is_open: ^bool, format: string, args: ..any) -> bool {
    was_open := is_open^
    interaction := set_value_interaction(is_open, !was_open)
    
    hot    := is_hot(parent.ui, interaction)
    active := is_active(parent.ui, interaction) || was_open
    
    theme := theme_button(hot, active)
    
    if ui_themed_button(parent, interaction, theme, format, ..args) {
        is_open^ = !was_open
    }
    
    result := is_open^
    
    return result
}

ui_radio_button :: proc (parent: ^UI_Element, target: ^$T, value: T, format: string, args: ..any) -> bool {
    active := target^ == value
    
    interaction := set_value_interaction(target, value)
    hot := is_hot(parent.ui, interaction)
    active  = is_active(parent.ui, interaction) || active
    
    theme := theme_button(hot, active)
    clicked := ui_themed_button(parent, interaction, theme, format, ..args)
    
    result: bool
    if clicked {
        if !active {
            target^ = value
            result = true
        }
    }
    
    return result
}

ui_themed_button :: proc (parent: ^UI_Element, interaction: Interaction, theme: Theme, format: string, args: ..any) -> bool {
    text := tprint(format, ..args)
    text_size := measure_text(parent, text)
    
    button := begin_ui_element_calculated(parent)
    ui_element_set_interaction(&button, interaction)
    ui_element_set_border(&button, theme.outline)
    ui_element_set_padding(&button, { 4, 2 })
        text_element := begin_ui_element(&button, &text_size)
        end_ui_element(&text_element)
    end_ui_element(&button)
    
    draw_rectangle(button.bounds, theme.background)
    draw_text(parent, text, text_element.bounds.min, theme.text, theme.text_shadow)
    
    result: bool
    // @todo(viktor): this should be inside end_ui_element
    if rect_contains(button.bounds, parent.ui.mouse_p) && is_ended(parent.ui, interaction) {
        result = true
    }
    
    return result
}

////////////////////////////////////////////////

ui_mover :: proc (ui: ^UI, drag: ^v2, size: v2) -> bool {
    rect := rect_min_dimension(drag^, size)
    
    interaction := Interaction { kind = .Move, target = drag }
    if rect_contains(rect, ui.mouse_p) {
        ui.next_hot_interaction = interaction
    }
    
    result: bool
    if is_active(ui, interaction) {
        drag^ += ui.mouse_dp
        result = true
    }
    
    // @theme
    handle := rect_min_dimension(drag^, size)
    draw_rectangle_outline(handle, 1, Black)
    draw_rectangle(handle, Isabelline)
    
    return result
}

// @todo(viktor): dragger should be only for unclamped values, for clamped values there should just be a slider that shows the user the range and where the current value lies within that range
ui_dragger :: proc { ui_dragger_float, ui_dragger_int, ui_dragger_clamp_float, ui_dragger_clamp_int, ui_dragger_clamp_uint }
// @copypasta clamps
ui_dragger_clamp_float :: proc (layout: ^Layout, value: ^f32, speed, min, max: f32, format: string, args: ..any, flags := DraggerFlags{}) -> bool {
    interaction := Interaction{ kind = .Drag, target = value }
    
    changed, released := ui_dragger_base(layout, value, speed, interaction, flags, format, ..args)
    if changed {
        value^ = clamp(value^, min, max)
    }
    
    return released
}
ui_dragger_clamp_int :: proc (layout: ^Layout, value: ^$I, format: string, args: ..any, speed: f32 = 1, min: int = min(int), max: int = max(int), logarithmic := false) -> bool where !intrinsics.type_is_unsigned(I), intrinsics.type_is_integer(I) {
    before := value^
    released := ui_dragger_int(layout, value, format, ..args, speed = speed, logarithmic = logarithmic)
    if value^ != before {
        value^ = clamp(value^, cast(I) min, cast(I) max)
    }
    
    return released
}
ui_dragger_clamp_uint :: proc (layout: ^Layout, value: ^$T, format: string, args: ..any, speed: f32 = 1, #any_int min: u64 = min(u64), #any_int max: u64 = max(u64), logarithmic := false) -> bool where intrinsics.type_is_unsigned(T), intrinsics.type_is_integer(T) {
    before := value^
    released := ui_dragger_int(layout, value, format, ..args, speed = speed, logarithmic = logarithmic)
    if value^ != before {
        value^ = clamp(value^, cast(T) min, cast(T) max)
    }
    
    return released
}
ui_dragger_int :: proc (layout: ^Layout, value: ^$I, format: string, args: ..any, speed: f32 = 1, logarithmic := false) -> bool where intrinsics.type_is_integer(I) {
    interaction := Interaction{ kind = .Drag, target = value }
    
    temp := cast(f32) value^
    flags : DraggerFlags
    if logarithmic do flags += { .logarithmic }
    changed, released := ui_dragger_base(layout, &temp, speed, interaction, flags, format, ..args)
    
    if changed {
        next := round(I, temp)
        changed = next != value^
        value^  = next
    }
    
    released = is_ended(layout.ui, interaction)
    
    return released
}
ui_dragger_float :: proc (layout: ^Layout, value: ^f32, format: string, args: ..any, speed: f32 = 1, min := min(f32), max := max(f32), logarithmic := false) -> bool {
    interaction := Interaction{ kind = .Drag, target = value }
    
    flags : DraggerFlags
    if logarithmic do flags += { .logarithmic }
    changed, released := ui_dragger_base(layout, value, speed, interaction, flags, format, ..args)
    
    if changed {
        value^ = clamp(value^, min, max)
    }
    return released
}

ui_dragger_base :: proc (layout: ^Layout, value: ^f32, speed: f32, interaction: Interaction, flags: DraggerFlags, format: string, args: ..any) -> (changed: bool, released: bool) {
    __ui_dragger_raw(layout, interaction, format, ..args)
    
    if is_active(layout.ui, interaction) {
        before := value^
        val    := value^
        
        speed := speed
        if .logarithmic in flags {
            val = math.ln(val)
            speed /= 1000
        }
        
        val += speed * layout.ui.mouse_dp.x
        
        if .logarithmic in flags {
            val = math.exp(val)
        }
        
        value^  = val
        changed = val != before
    }
    
    released = is_ended(layout.ui, interaction)
    
    return changed, released
}

__ui_dragger_raw :: proc (layout: ^Layout, interaction: Interaction, format: string, args: ..any) {
    // @theme
    text_color := Jasmine
    if is_hot(layout.ui, interaction) {
        text_color = Isabelline
    } else if is_active(layout.ui, interaction) {
        text_color = Isabelline
    }
    
    text := tprint(format, ..args)
    size := measure_text(layout, text)
    
    text_p := layout.allocated.min
    draw_text(layout, text, text_p, text_color)
    layout_advance(layout, size)
    
    rect := rect_min_dimension(text_p, size) 
    if rect_contains(rect, layout.ui.mouse_p) {
        layout.ui.next_hot_interaction = interaction
    }
}

////////////////////////////////////////////////

ui_color_picker :: proc (layout: ^Layout, rgb: ^v3, format: string) -> bool {
    ui_text(layout, format)
    layout_advance(layout, layout.spacing)
    
    size :: 40
    bounds := rect_min_dimension(layout.allocated.min, size)
    layout_advance_2_dim(layout, size + {40, 0})
    layout_advance(layout, layout.spacing)
    
    color := color_to_rl(rgb^)
    before := color
    
    rl.GuiColorPicker(rect_to_rl(bounds), "", &color)
    
    result := color != before
    rgb^ = color_from_rl(color).rgb
    
    return result
}

////////////////////////////////////////////////

ui_text :: proc (layout: ^Layout, format: string, args: ..any) {
    text := tprint(format, ..args)
    text_p := layout.allocated.min
    size := measure_text(layout, text)
    // @theme
    draw_text(layout, text, text_p, Jasmine)
    layout_advance(layout, size)
}

ui_progress_bar :: proc (layout: ^Layout, percentage: f32, width: f32) {
    border_size :: 2
    size := v2{width, layout.font_size - border_size*2}
    at := layout.allocated.min
    rect     := rect_min_dimension(at+border_size, size)
    progress := rect_min_dimension(at+border_size, size * v2{percentage, 1}) 
    
    // @theme
    draw_rectangle_outline(rect, border_size, DarkGreen)
    draw_rectangle(rect, Green)
    draw_rectangle(progress, Isabelline)
    
    layout_advance(layout, size)
    
    layout_advance(layout, layout.spacing)
}

////////////////////////////////////////////////

measure_text :: proc (layout: ^Layout, text: string) -> v2 {
    ctext := ctprint(text)
    result := rl.MeasureTextEx(layout.font, ctext, layout.font_size, 1)
    return result
}

// @theme
draw_text :: proc (layout: ^Layout, text: string, p: v2, color: v4, shadow_color := Black) {
    ctext := ctprint(text)
    if shadow_color.a != 0 {
        rl.DrawTextEx(layout.font, ctext, p+2, layout.font_size, 1, color_to_rl(shadow_color))
    }
    rl.DrawTextEx(layout.font, ctext, p,   layout.font_size, 1, color_to_rl(color))
}

draw_rectangle :: proc (rect: Rectangle2, color: v4) {
    rl.DrawRectangleRec(rect_to_rl(rect), color_to_rl(color))
}

draw_rectangle_outline :: proc (rect: Rectangle2, thickness: v2, color: v4) {
    dim    := rect_get_dimension(rect)
    center := rect_get_center(rect)
    
    top := rect_center_dimension(v2{center.x, rect.min.y-thickness.y/2}, v2{dim.x + 2*thickness.x, thickness.y})
    bot := rect_center_dimension(v2{center.x, rect.max.y+thickness.y/2}, v2{dim.x + 2*thickness.x, thickness.y})
    
    lef := rect_center_dimension(v2{rect.min.x-thickness.x/2, center.y}, v2{thickness.x, dim.y})
    rig := rect_center_dimension(v2{rect.max.x+thickness.x/2, center.y}, v2{thickness.x, dim.y})
    
    draw_rectangle(top, color)
    draw_rectangle(bot, color)
    draw_rectangle(lef, color)
    draw_rectangle(rig, color)
}

////////////////////////////////////////////////

rect_to_rl :: proc (rect: Rectangle2) -> rl.Rectangle {
    result: rl.Rectangle
    
    result.x = rect.min.x
    result.y = rect.min.y
    result.width  = rect_get_dimension(rect).x
    result.height = rect_get_dimension(rect).y
    
    return result
}

color_to_rl :: proc (color: $V) -> rl.Color {
    bytes := color_to_u8(color)
    result := transmute(rl.Color) bytes
    return result
}

color_from_rl :: proc (color: rl.Color) -> v4 {
    bytes := cast(Color) color
    result := color_from_u8(bytes)
    return result
}

////////////////////////////////////////////////

Layout :: UI_Element
UI_Element :: struct {
    using xxx: xx,
    
    parent: ^UI_Element,
    
    flags:       UI_Element_Flags,
    interaction: Interaction,
    
    border_color: v4,
    spacing: v2,
    padding: v2,
    
    size_kind: UI_Element_Size_Kind,
    
    ////////////////////////////////////////////////
    // Fixed Size
    size: ^v2,
    
    ////////////////////////////////////////////////
    // Allocated Size
    allocated: Rectangle2,

    ////////////////////////////////////////////////
    // Calculated Size
    child_p:   v2,
    child_min: v2,
    child_max: v2,
    child_count: f32,
    
    ////////////////////////////////////////////////
    // result for user
    bounds:  Rectangle2,
        
    ////////////////////////////////////////////////
    // Linear Layout
    base_x: f32,
    // @naming
    size_children: v2,
}

xx :: struct {
    ui: ^UI,
    font: rl.Font,
    font_size: f32,
    
    dt: f32,
}

UI_Element_Size_Kind :: enum {
    Allocated,
    Fixed,   // by user
    Calculated, // from children
}

UI_Element_Flags :: bit_set[UI_Element_Flag]
UI_Element_Flag :: enum {
    has_interaction,
    has_border,
    
    grow_horizontal,
}

begin_ui_element :: proc (parent: ^UI_Element, size: ^v2) -> UI_Element {
    result := make_ui_element(parent)
    
    result.size      = size
    result.size_kind = .Fixed
    
    return result
}

begin_ui_element_calculated :: proc (parent: ^UI_Element) -> UI_Element {
    result := make_ui_element(parent)
    result.size_kind = .Calculated
    
    // @todo(viktor): 
    switch parent.size_kind {
    case .Fixed:   unimplemented()
    case .Allocated:  result.child_min = parent.allocated.min
    case .Calculated: result.child_min = parent.child_p
    }
    result.child_p   = result.child_min
    result.child_max = result.child_min
    
    result.flags += { .grow_horizontal }
    
    return result
}

make_ui_element :: proc (parent: ^UI_Element) -> UI_Element {
    result: UI_Element
    
    result.xxx = parent.xxx
    result.parent = parent
    
    return result
}

// @api should .interaction just be a maybe, even if we already have a .flags?
ui_element_set_interaction :: proc (element: ^UI_Element, interaction: Interaction) {
    element.flags      += { .has_interaction }
    element.interaction = interaction
}

ui_element_set_border :: proc (element: ^UI_Element, color := Red) {
    element.flags += { .has_border }
    element.border_color = color
}

ui_element_set_padding :: proc (element: ^UI_Element, padding: v2) {
    element.padding = padding
    switch element.size_kind {
    case .Fixed, .Allocated: // nothing
    case .Calculated: 
        element.child_min += padding
        element.child_p   += padding
        element.child_max += padding * 2
    }
}

end_ui_element :: proc (element: ^UI_Element) {
    // @todo(viktor): resize interactions
    
    Border_Size :: 2
    border: v2
    if .has_border in element.flags {
        border = Border_Size
    }
    
    parent := element.parent
    total_min: v2
    switch parent.size_kind {
    case .Fixed:   unimplemented()
    case .Allocated:  total_min = parent.allocated.min
        
    case .Calculated:
        if parent.child_count != 0 {
            mask  := .grow_horizontal in parent.flags ? v2{ 1, 0 } : v2{ 0, 1 }
            space := parent.spacing * mask
            parent.child_p   += space
            parent.child_max += space
        }
        
        total_min = parent.child_p
    }
    parent.child_count += 1
    
    if .has_border in parent.flags {
        total_min += Border_Size
    }
    
    element_dim: v2
    switch element.size_kind {
        case .Allocated:  unimplemented()
        case .Fixed:      element_dim = element.size^
        case .Calculated: element_dim = (element.child_max + element.padding) - element.child_min
    }
    
    total_dim := element_dim + border * 2
    total_bounds  := rect_min_dimension(total_min,          total_dim)
    element.bounds = rect_min_dimension(total_min + border, element_dim)
    
    if border != 0 {
        draw_rectangle_outline(element.bounds, border, element.border_color)
    }
    
    ui := element.ui
    if .has_interaction in element.flags && rect_contains(element.bounds, ui.mouse_p) {
        ui.next_hot_interaction = element.interaction
    }
    
    switch parent.size_kind {
    case .Fixed: // nothing
    
    case .Allocated:
        if .grow_horizontal in parent.flags {
            parent.allocated.min.x = total_bounds.max.x
            parent.size_children.y = max(parent.size_children.y, total_dim.y)
        } else {
            parent.allocated.min.y = total_bounds.max.y
        }
        
    case .Calculated:
        if .grow_horizontal in parent.flags {
            parent.child_p.x   += total_dim.x
            parent.child_max.x += total_dim.x
            parent.child_max.y  = max(parent.child_max.y, total_bounds.max.y)
        } else {
            parent.child_p.y   += total_dim.y
            parent.child_max.x  = max(parent.child_max.x, total_bounds.max.x)
            parent.child_max.y += total_dim.y
        }
    }
}

////////////////////////////////////////////////

theme_button :: proc (is_hot: bool, is_active: bool) -> Theme {
    result: Theme
    result.outline     = DarkGreen
    result.background  = DarkGreen
    result.text        = Jasmine
    result.text_shadow = Black
    if is_hot {
        result.outline = Green
        result.background = Isabelline
        result.text = Green
        result.text_shadow = 0
    } else if is_active {
        result.background = Green
        result.text = Isabelline
    }
    
    return result
}