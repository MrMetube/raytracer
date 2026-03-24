package main

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
        Object_Index,
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

begin_ui :: proc (ui: ^UI) {
    ui.mouse_p  = rl.GetMousePosition()
    ui.mouse_dp = rl.GetMouseDelta()
}


interact :: proc (ui: ^UI) {
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
        // Resize Move
        
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
        // auto detect based on type of value
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
ui_button :: proc (layout: ^Layout, interaction: Interaction, format: string, args: ..any) -> bool {
    result := ui_button_highlighted(layout, interaction, false, format, ..args)
    return result
}

// @cleanup what is an interaction in this once we have drags and sliders and moves
ui_button_highlighted :: proc (layout: ^Layout, interaction: Interaction, is_highlighted: bool, format: string, args: ..any) -> bool {
    text := tprint(format, ..args)
    
    dim := measure_text(layout, text)
    text_p := layout.at
    size := rectangle_min_dimension(text_p, dim)
    size = rectangle_add_radius(size, v2{4, 1})
    
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
    
    draw_rectangle_outline(size, 1, outline)
    draw_rectangle(size, background)
    draw_text(layout, text, text_p, text_color, shadow_color)
    layout_advance_2(layout, rectangle_get_dimension(size)) // @api
    
    result: bool
    if rectangle_contains(size, layout.ui.mouse_p) {
        layout.ui.next_hot_interaction = interaction
        result = is_ended(layout.ui, interaction)
    }
    
    return result
}

ui_mover :: proc (ui: ^UI, drag: ^v2, size: v2) -> bool {
    rect := rectangle_min_dimension(drag^, size)
    
    interaction := Interaction { kind = .Move, target = drag }
    if rectangle_contains(rect, ui.mouse_p) {
        ui.next_hot_interaction = interaction
    }
    
    result: bool
    if is_active(ui, interaction) {
        drag^ += ui.mouse_dp
        result = true
    }
    
    // @theme
    handle := rectangle_min_dimension(drag^, size)
    draw_rectangle_outline(handle, 1, Black)
    draw_rectangle(handle, Isabelline)
    
    return result
}

ui_dragger :: proc { ui_dragger_base, ui_dragger_clamp }
// @copypasta
ui_dragger_clamp :: proc (layout: ^Layout, value: ^f32, speed, min, max: f32, format: string, args: ..any, flags := SliderFlags{}) -> (changed: bool, released: bool) {
    interaction := Interaction{ kind = .Drag, target = value }
    before := value^
    
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
    
    rect := rectangle_min_dimension(text_p, size) 
    if rectangle_contains(rect, layout.ui.mouse_p) {
        layout.ui.next_hot_interaction = interaction
    }
    
    if is_active(layout.ui, interaction) {
        min := min
        max := max
        val := value^
        
        if .logarithmic in flags {
            log_min := math.ln(min)
            log_max := math.ln(max)
            log_val := math.ln(val)
            
            log_val += speed/1000 * layout.ui.mouse_dp.x
            log_val = clamp(log_val, log_min, log_max)
            
            val = math.exp(log_val)
        } else {
            val += speed * layout.ui.mouse_dp.x
            val = clamp(val, min, max)
        }
        
        value^ = val
        changed = val != before
    }
    
    released = is_ended(layout.ui, interaction)
    
    return changed, released
}
ui_dragger_base :: proc (layout: ^Layout, value: ^f32, speed: f32, format: string, args: ..any) -> (changed: bool, released: bool) {
    interaction := Interaction{ kind = .Drag, target = value }
    
    before := value^
    
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
    
    rect := rectangle_min_dimension(text_p, size) 
    if rectangle_contains(rect, layout.ui.mouse_p) {
        layout.ui.next_hot_interaction = interaction
    }
    
    if is_active(layout.ui, interaction) {
        val := value^
        val += speed * layout.ui.mouse_dp.x
        
        value^ = val
        changed = val != before
    }
    
    released = is_ended(layout.ui, interaction)
    
    return changed, released
}

////////////////////////////////////////////////

ui_toggle :: proc (layout: ^Layout, condition: ^bool, text: string) {
    interaction := set_value_interaction(condition, !condition^)
    pressed := ui_button_highlighted(layout, interaction, condition^, text)
    if pressed {
        condition^ = !condition^
    }
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
    rect     := rectangle_min_dimension(layout.at+border_size, size)
    progress := rectangle_min_dimension(layout.at+border_size, size * v2{percentage, 1}) 
    
    // @theme
    draw_rectangle_outline(rect, border_size, DarkGreen)
    draw_rectangle(rect, Green)
    draw_rectangle(progress, Isabelline)
    
    layout_advance_2(layout, size)
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
    dim    := rectangle_get_dimension(rect)
    center := rectangle_get_center(rect)
    
    top := rectangle_center_dimension(v2{center.x, rect.min.y-thickness/2}, v2{dim.x + 2*thickness, thickness})
    bot := rectangle_center_dimension(v2{center.x, rect.max.y+thickness/2}, v2{dim.x + 2*thickness, thickness})
    
    lef := rectangle_center_dimension(v2{rect.min.x-thickness/2, center.y}, v2{thickness, dim.y})
    rig := rectangle_center_dimension(v2{rect.max.x+thickness/2, center.y}, v2{thickness, dim.y})
    
    draw_rectangle(top, color)
    draw_rectangle(bot, color)
    draw_rectangle(lef, color)
    draw_rectangle(rig, color)
}