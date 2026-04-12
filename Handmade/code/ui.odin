package main

import "base:intrinsics"
import "base:builtin"
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

// @todo(viktor): @api collapse into begin ui_element set_interaction(used for color) set_outline, set_text, end_ui_element
// @cleanup what is an interaction in this once we have drags and sliders and moves
ui_button :: proc (layout: ^Layout, interaction: Interaction, format: string, args: ..any, is_highlighted := false) -> bool {
    text := tprint(format, ..args)
    
    size := measure_text(layout, text)
    text_p := layout.at
    rect := rect_min_dimension(text_p, size)
    rect = rect_add_radius(rect, v2{4, 1})
    
    // @theme
    outline      := DarkGreen
    background   := DarkGreen
    text_color   := Jasmine
    shadow_color := Black
    if is_hot(layout.ui, interaction) {
        outline = Green
        background = Isabelline
        text_color = Green
        shadow_color = 0
    } else if is_active(layout.ui, interaction) || is_highlighted {
        background = Green
        text_color = Isabelline
    }
    
    draw_rectangle_outline(rect, 1, outline)
    draw_rectangle(rect, background)
    draw_text(layout, text, text_p, text_color, shadow_color)
    layout_advance_2(layout, rect_get_dimension(rect)) // @api
    
    result: bool
    if rect_contains(rect, layout.ui.mouse_p) {
        layout.ui.next_hot_interaction = interaction
        result = is_ended(layout.ui, interaction)
    }
    
    layout_pad(layout)
    
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
    
    text_p := layout.at
    draw_text(layout, text, text_p, text_color)
    layout_advance_2(layout, size)
    
    rect := rect_min_dimension(text_p, size) 
    if rect_contains(rect, layout.ui.mouse_p) {
        layout.ui.next_hot_interaction = interaction
    }
}

////////////////////////////////////////////////

ui_color_picker :: proc (layout: ^Layout, rgb: ^v3, format: string) -> bool {
    ui_text(layout, format)
    layout_pad(layout)
    
    size :: 40
    bounds := rect_min_dimension(layout.at, size)
    layout_advance_2(layout, size + {40, 0})
    layout_pad(layout)
    
    color := color_to_rl(rgb^)
    before := color
    
    rl.GuiColorPicker(rect_to_rl(bounds), "", &color)
    
    result := color != before
    rgb^ = color_from_rl(color).rgb
    
    return result
}

////////////////////////////////////////////////

ui_toggle :: proc (layout: ^Layout, condition: ^bool, text: string) -> bool {
    interaction := set_value_interaction(condition, !condition^)
    pressed := ui_button(layout, interaction, text, is_highlighted = condition^)
    if pressed {
        condition^ = !condition^
    }
    return pressed
}

ui_collapser :: proc (layout: ^Layout, is_open: ^bool, text: string) -> bool {
    ui_toggle(layout, is_open, text)
    result := is_open^
    return result
}

////////////////////////////////////////////////

ui_text :: proc (layout: ^Layout, format: string, args: ..any) {
    text := tprint(format, ..args)
    text_p := layout.at
    size := measure_text(layout, text)
    // @theme
    draw_text(layout, text, text_p, Jasmine)
    layout_advance_2(layout, size)
}

ui_progress_bar :: proc (layout: ^Layout, percentage: f32, width: f32) {
    border_size :: 2
    size := v2{width, layout.font_size - border_size*2}
    rect     := rect_min_dimension(layout.at+border_size, size)
    progress := rect_min_dimension(layout.at+border_size, size * v2{percentage, 1}) 
    
    // @theme
    draw_rectangle_outline(rect, border_size, DarkGreen)
    draw_rectangle(rect, Green)
    draw_rectangle(progress, Isabelline)
    
    layout_advance_2(layout, size)
    
    layout_pad(layout)
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

draw_rectangle_outline :: proc (rect: Rectangle2, thickness: f32, color: v4) {
    dim    := rect_get_dimension(rect)
    center := rect_get_center(rect)
    
    top := rect_center_dimension(v2{center.x, rect.min.y-thickness/2}, v2{dim.x + 2*thickness, thickness})
    bot := rect_center_dimension(v2{center.x, rect.max.y+thickness/2}, v2{dim.x + 2*thickness, thickness})
    
    lef := rect_center_dimension(v2{rect.min.x-thickness/2, center.y}, v2{thickness, dim.y})
    rig := rect_center_dimension(v2{rect.max.x+thickness/2, center.y}, v2{thickness, dim.y})
    
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