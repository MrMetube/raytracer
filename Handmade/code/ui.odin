package main

import "base:intrinsics"
import "base:runtime"
import "core:math"
import rl "vendor:raylib"

UI :: struct {
    next_hot_interaction: Interaction,
    hot_interaction:      Interaction,
    active_interaction:   Interaction,
    ended_interaction:    Interaction, // @naming
    
    mouse_p:  v2,
    mouse_dp: v2,
    dt: f32,
    mouse_buttons: [Mouse_Button_Kind] Mouse_Button,
    
    elements: [dynamic; 256] Element,
    
    ////////////////////////////////////////////////
    
    font: rl.Font,
    font_size: f32,
}

Mouse_Button :: struct {
    down, pressed, released, up: bool,
}

Mouse_Button_Kind :: enum {
    left,
    middle,
    right,
    /* side, extra, forward, back */
}

the_ui: ^UI
parent_stack: [dynamic; 256] ^Element

Interaction :: struct {
    kind: Interaction_Kind,
    
    id: Interaction_Id,
    
    buttons: bit_set[Mouse_Button_Kind],
}

Interaction_Id :: struct {
    pointer:  pmm,
    index:    int,
    location: runtime.Source_Code_Location,
}

Interaction_Kind :: enum {
    None,
    NOP,
    SetValue,
    Drag,
    Move,
    Select,
}

Theme :: struct {
    border:     v4,
    background: v4,
    text:       v4,
    shadow:     v4,
}

////////////////////////////////////////////////

// @todo(viktor): move sizing to be per axis
Element :: struct {
    parent:      ^Element,
    first_child: ^Element,
    next_child:  ^Element,
    
    flags:       UI_Flags,
    interaction: Interaction,
    
    spacing: v2,
    padding: v2,
    
    theme: Theme,
    text: string,
    
    size_kind: UI_Size_Kind,
    
    ////////////////////////////////////////////////
    // Fixed Size
    size: v2,
    
    ////////////////////////////////////////////////
    // Calculated Size
    child_offset: v2,
    child_count:  f32,
    
    ////////////////////////////////////////////////
    // result for user
    bounds: Rectangle2,
}

UI_Size_Kind :: enum {
    Allocated,
    Fixed,      // by user
    Calculated, // from children
}

UI_Flags :: bit_set[UI_Flag]
UI_Flag :: enum {
    has_interaction,
    has_border,
    has_background,
    has_text,
    
    grow_horizontal,
}

////////////////////////////////////////////////

ui_init :: proc (ui: ^UI, font: rl.Font, font_size: f32) {
    ui.font = font
    ui.font_size = font_size
    
    rl.GuiEnable()
    rl.GuiSetFont(ui.font)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiDefaultProperty.TEXT_SIZE, cast(i32) ui.font_size)
    
    // @theme
    Background := color_to_u8(DarkGreen)
    Foreground := color_to_u8(Jasmine)
    Highlight  := color_to_u8(Green)
    Focus      := color_to_u8(Isabelline)
    None       := color_to_u8(v4{})
    
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_NORMAL,     Foreground)
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_PRESSED,    Focus)
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_FOCUSED,    Highlight)
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_DISABLED,   Highlight)
    
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_NORMAL,     Background)
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_FOCUSED,    Focus)
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_PRESSED,    Highlight)
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_DISABLED,   Background)
    
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_NORMAL,   None)
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_FOCUSED,  Highlight)
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_PRESSED,  Background)
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_DISABLED, None)
    
    rlGuiSetColor :: proc (control: rl.GuiControl, property: rl.GuiControlProperty, value: Color) {
        rl.GuiSetStyle(control, auto_cast property, transmute(i32) value.abgr)
    }
}

begin_ui :: proc (ui: ^UI, delta_time: f32) {
    ui.mouse_p  = rl.GetMousePosition()
    ui.mouse_dp = rl.GetMouseDelta()
    ui.dt = delta_time
    
    for rl_button, kind in ([Mouse_Button_Kind] rl.MouseButton {
        .left   = .LEFT,
        .middle = .MIDDLE,
        .right  = .RIGHT,
    }) {
        ui.mouse_buttons[kind].down     = rl.IsMouseButtonDown(rl_button)
        ui.mouse_buttons[kind].pressed  = rl.IsMouseButtonPressed(rl_button)
        ui.mouse_buttons[kind].released = rl.IsMouseButtonReleased(rl_button)
        ui.mouse_buttons[kind].up       = rl.IsMouseButtonUp(rl_button)
    }
    
    clear(&ui.elements)
    
    the_ui = ui
}

end_ui :: proc (ui: ^UI) {
    the_ui = nil
}

interact :: proc (ui: ^UI) {
    // @todo(viktor): set cursor based on active.interaction
    // if none are active based on hot_interaction
    ui.ended_interaction = {}
    
    switch ui.active_interaction.kind {
    case .None: // nothing
    case .NOP, .SetValue, .Select, .Move: // @note(viktor): nothing
    case .Drag:
        width  := cast(f32) rl.GetScreenWidth()
        height := cast(f32) rl.GetScreenHeight()
        
        screen_size := v2 { width, height }
        padding :: 1
        
        new_p := ui.mouse_p
        
        wrapped := false
        for axis in 0..<2 {
            if ui.mouse_p[axis] <= 0 {
                new_p[axis] = screen_size[axis] - 1 - padding
                wrapped = true
            } else if ui.mouse_p[axis] >= screen_size[axis] - 1 {
                new_p[axis] = padding
                wrapped = true
            }
        }
        
        if wrapped {
            rl.SetMousePosition(cast(i32) new_p.x, cast(i32) new_p.y)
            ui.mouse_dp = {0, 0}
        }
    }
    
    if ui.active_interaction.kind != .None {
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
    switch ui.active_interaction.kind {
    case .None: unreachable()
    case .NOP:  // nothing
    case .SetValue, .Drag, .Select, .Move:
        ui.ended_interaction = ui.active_interaction
    }
    
    ui.active_interaction = {}
}

is_interacting_press :: proc (ui: ^UI) -> bool {
    it := ui.active_interaction
    if ui.active_interaction.kind == .None {
        it = ui.hot_interaction
    }
    
    result: bool
    for button in it.buttons {
        result ||= mouse_button_pressed(ui, button)
    }
    
    return result
}

is_interacting_release :: proc (ui: ^UI) -> bool {
    it := ui.active_interaction
    if ui.active_interaction.kind == .None {
        it = ui.hot_interaction
    }
    
    result: bool
    for button in it.buttons {
        result ||= mouse_button_released(ui, button)
    }
    
    return result
}

mouse_button_pressed  :: proc (ui: ^UI, button: Mouse_Button_Kind) -> bool { return ui.mouse_buttons[button].pressed  }
mouse_button_released :: proc (ui: ^UI, button: Mouse_Button_Kind) -> bool { return ui.mouse_buttons[button].released }
mouse_button_up       :: proc (ui: ^UI, button: Mouse_Button_Kind) -> bool { return ui.mouse_buttons[button].up       }
mouse_button_down     :: proc (ui: ^UI, button: Mouse_Button_Kind) -> bool { return ui.mouse_buttons[button].down     }

////////////////////////////////////////////////

is_hot :: proc (ui: ^UI, interaction: Interaction) -> bool {
    result := interaction_equal(ui.hot_interaction, interaction)
    return result
}

is_active :: proc (ui: ^UI, interaction: Interaction) -> bool {
    result := interaction_equal(ui.active_interaction, interaction)
    return result
}

// @naming
is_ended :: proc (ui: ^UI, interaction: Interaction) -> bool {
    result := interaction_equal(ui.ended_interaction, interaction)
    return result
}

////////////////////////////////////////////////

interaction_make :: proc (kind: Interaction_Kind, pointer: ^$T, #any_int index: int = 0, loc := #caller_location) -> Interaction {
    result: Interaction
    result.kind   = .SetValue
    
    result.buttons = { .left }
    
    result.id.pointer  = pointer
    result.id.index    = index
    result.id.location = loc
    
    return result
}

interaction_equal :: proc (a, b: Interaction) -> bool {
    result := a.id == b.id
    return result
}

interaction_buttons :: proc { interaction_buttons_1, interaction_buttons_ref }
interaction_buttons_1 :: proc (interaction: Interaction, left, middle, right: bool) -> Interaction {
    result := interaction
    
    result.buttons = {}
    if left   { result.buttons += { .left }   }
    if middle { result.buttons += { .middle } }
    if right  { result.buttons += { .right }  }
    
    return result
}

interaction_buttons_ref :: proc (interaction: ^Interaction, left, middle, right: bool) {
    interaction^ = interaction_buttons_1(interaction^, left, middle, right)
}

set_value_interaction_ :: proc (target: ^$T, index := 0, loc := #caller_location) -> Interaction {
    result := interaction_make(.SetValue, target, index, loc)
    return result
}

////////////////////////////////////////////////

// @cleanup what is an interaction in this once we have drags and sliders and moves
ui_button :: proc (interaction: Interaction, format: string, args: ..any) -> bool {
    hot    := is_hot(the_ui, interaction)
    active := is_active(the_ui, interaction)
    
    theme  := theme_button(hot, active)
    result := ui_themed_button(interaction, theme, format, ..args)
    
    return result
}

ui_toggle :: proc (condition: ^bool, format: string, args: ..any, loc := #caller_location) -> bool {
    interaction := set_value_interaction_(condition, loc = loc)
    
    hot    := is_hot(the_ui, interaction)
    active := is_active(the_ui, interaction) || condition^
    
    theme   := theme_button(hot, active)
    clicked := ui_themed_button(interaction, theme, format, ..args)
    
    if clicked {
        condition^ = !condition^
    }
    
    return clicked
}

ui_collapser :: proc (is_open: ^bool, format: string, args: ..any, loc := #caller_location) -> bool {
    was_open := is_open^
    interaction := set_value_interaction_(is_open, loc = loc)
    
    hot    := is_hot(the_ui, interaction)
    active := is_active(the_ui, interaction) || was_open
    
    theme := theme_button(hot, active)
    if ui_themed_button(interaction, theme, format, ..args) {
        is_open^ = !was_open
    }
    
    result := is_open^
    
    return result
}

Communication_Radio :: struct {
    clicked:     bool,
    is_selected: bool,
}

ui_radio_button :: proc (target: ^$T, value: T, format: string, args: ..any, #any_int index := 0, loc := #caller_location) -> Communication_Radio {
    interaction := set_value_interaction_(target, index = index, loc = loc)
    
    hot    := is_hot(the_ui, interaction)
    active := is_active(the_ui, interaction) || target^ == value
    
    theme := theme_button(hot, active)
    clicked := ui_themed_button(interaction, theme, format, ..args)
    
    result: Communication_Radio
    if clicked {
        if !active {
            target^ = value
            result.clicked = true
        }
    }
    
    if target^ == value {
        result.is_selected = true
    }
    
    return result
}

ui_themed_button :: proc (interaction: Interaction, theme: Theme, format: string, args: ..any) -> bool {
    // @api begin_ui_element_sized_by_text? or something to not format and measure twice
    text := tprint(format, ..args)
    text_size := measure_text(the_ui, text)
    
    button := begin_ui_element(text_size)
    ui_element_interaction(button, interaction)
    ui_element_border(button, theme.border)
    ui_element_text(button, theme.text, theme.shadow, format, ..args)
    ui_element_background(button, theme.background)
    button.padding = { 4, 2 }
    end_ui_element(button)
    
    result: bool
    // @todo(viktor): this should be inside end_ui_element
    if rect_contains(button.bounds, the_ui.mouse_p) && is_ended(the_ui, interaction) {
        result = true
    }
    
    return result
}

////////////////////////////////////////////////

ui_mover :: proc (ui: ^UI, drag: ^v2, size: v2, loc := #caller_location) -> bool {
    rect := rect_min_dimension(drag^, size)
    
    interaction := interaction_make(.Move, drag, loc = loc)
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

////////////////////////////////////////////////

ui_dragger_01 :: proc (value: ^f32, format: string, args: ..any) -> bool {
    return ui_dragger_float(value, format, ..args, speed = 0.001, min = 0, max = 1)
}

// @todo(viktor): dragger should be only for unclamped values, for clamped values there should just be a slider that shows the user the range and where the current value lies within that range
ui_dragger :: proc { ui_dragger_float, ui_dragger_int, ui_dragger_clamp_float, ui_dragger_clamp_int, ui_dragger_clamp_uint }
// @copypasta clamps
ui_dragger_clamp_float :: proc (value: ^f32, speed, min, max: f32, format: string, args: ..any, logarithmic := false, loc := #caller_location) -> bool {
    interaction := interaction_make(.Drag, value, loc = loc)
    
    result := ui_dragger_base(value, speed, interaction, logarithmic, format, ..args)
    if result.changed {
        value^ = clamp(value^, min, max)
    }
    
    return result.released
}
ui_dragger_clamp_int :: proc (value: ^$I, format: string, args: ..any, speed: f32 = 1, min: int = min(int), max: int = max(int), logarithmic := false) -> bool where !intrinsics.type_is_unsigned(I), intrinsics.type_is_integer(I) {
    before := value^
    released := ui_dragger_int(value, format, ..args, speed = speed, logarithmic = logarithmic)
    if value^ != before {
        value^ = clamp(value^, cast(I) min, cast(I) max)
    }
    
    return released
}
ui_dragger_clamp_uint :: proc (value: ^$T, format: string, args: ..any, speed: f32 = 1, #any_int min: u64 = min(u64), #any_int max: u64 = max(u64), logarithmic := false) -> bool where intrinsics.type_is_unsigned(T), intrinsics.type_is_integer(T) {
    before := value^
    released := ui_dragger_int(value, format, ..args, speed = speed, logarithmic = logarithmic)
    if value^ != before {
        value^ = clamp(value^, cast(T) min, cast(T) max)
    }
    
    return released
}
ui_dragger_int :: proc (value: ^$I, format: string, args: ..any, speed: f32 = 1, logarithmic := false, loc := #caller_location) -> bool where intrinsics.type_is_integer(I) {
    interaction := interaction_make(.Drag, value, loc = loc)
    
    temp := cast(f32) value^
    result := ui_dragger_base(&temp, speed, interaction, logarithmic, format, ..args)
    
    if result.changed {
        next := round(I, temp)
        result.changed = next != value^
        value^  = next
    }
    
    return result.released
}
ui_dragger_float :: proc (value: ^f32, format: string, args: ..any, speed: f32 = 1, min := min(f32), max := max(f32), logarithmic := false, loc := #caller_location) -> bool {
    interaction := interaction_make(.Drag, value, loc = loc)
    
    result := ui_dragger_base(value, speed, interaction, logarithmic, format, ..args)
    
    if result.changed {
        value^ = clamp(value^, min, max)
    }
    
    return result.released
}

Communication_Dragger :: struct {
    changed: bool, 
    released: bool,
}

ui_dragger_base :: proc (value: ^f32, speed: f32, interaction: Interaction, logarithmic: bool, format: string, args: ..any) -> Communication_Dragger {
    theme := theme_dragger(is_hot(the_ui, interaction) || is_active(the_ui, interaction))
    
    text := tprint(format, ..args)
    text_size := measure_text(the_ui, text)
    
    element := begin_ui_element(text_size)
    ui_element_interaction(element, interaction)
    ui_element_text(element, theme.text, theme.shadow, format, ..args)
    end_ui_element(element)
    
    result: Communication_Dragger
    if is_active(the_ui, interaction) {
        before := value^
        val    := value^
        
        speed := speed
        if logarithmic {
            val = math.ln(val)
            speed /= 1000
        }
        
        val += speed * the_ui.mouse_dp.x
        
        if logarithmic {
            val = math.exp(val)
        }
        
        value^  = val
        result.changed = val != before
    }
    
    result.released = is_ended(the_ui, interaction)
    
    return result
}

////////////////////////////////////////////////

ui_color_picker :: proc (rgb: ^v3, text: string) -> bool {
    parent := ui_peek_parent()
    
    ui_text("%v", text)
    layout_advance(parent, parent.spacing)
    
    theme := theme_button(false, false)
    
    picker := v2{ 40, 40 }
    size := picker + v2{ 20, 0 }
    element := begin_ui_element(size)
    ui_element_border(element, theme.border)
    end_ui_element(element)
    
    layout_advance(parent, parent.spacing)
    
    color := color_to_rl(rgb^)
    before := color
    
    rl.GuiColorPicker(rect_to_rl(rect_min_dimension(element.bounds.min, picker)), "", &color)
    
    result := color != before
    rgb^ = color_from_rl(color).rgb
    
    return result
}

////////////////////////////////////////////////

ui_text :: proc (format: string, args: ..any) {
    text := tprint(format, ..args)
    text_size := measure_text(the_ui, text)
    
    element := begin_ui_element(text_size)
    end_ui_element(element)
    
    theme := theme_button(false, false)
    draw_text(the_ui, text, element.bounds.min, theme.text, theme.shadow)
}

ui_progress_bar :: proc (percentage: f32, width: f32) {
    theme := theme_button(false, true)
    
    size := v2{width, the_ui.font_size}
    element := begin_ui_element(size)
    ui_element_border(element, theme.border)
    end_ui_element(element)
    
    rect     := element.bounds
    progress := rect_min_dimension(rect.min, rect_get_dimension(rect) * v2{percentage, 1}) 
    rest     := rect_min_max(v2{progress.max.x, rect.min.y}, rect.max)
    
    draw_rectangle(progress, theme.text)
    draw_rectangle(rest,     theme.background)
    text := tprint("%v", view_percentage(percentage))
    text_size := measure_text(the_ui, text)
    tt := rect_center_dimension(rect_get_center(element.bounds), text_size)
    draw_text(the_ui, text, tt.min, Jasmine, theme.shadow)
}

////////////////////////////////////////////////

measure_text :: proc (ui: ^UI, text: string) -> v2 {
    ctext := ctprint("%v", text)
    result := rl.MeasureTextEx(ui.font, ctext, ui.font_size, 1)
    return result
}

// @theme
draw_text :: proc (ui: ^UI, text: string, p: v2, color: v4, shadow_color := Black) {
    ctext := ctprint("%v", text)
    if shadow_color.a != 0 {
        rl.DrawTextEx(ui.font, ctext, p+2, ui.font_size, 1, color_to_rl(shadow_color))
    }
    rl.DrawTextEx(ui.font, ctext, p,   ui.font_size, 1, color_to_rl(color))
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

draw_texture :: proc (texture: rl.Texture, rect: Rectangle2, tint := White) {
    source := rect_zero_dimension(vec_cast(f32, texture.width, texture.height)) // @note(viktor): can be larger than 1 to repeat
    origin := v2{0,0}
    rl.DrawTexturePro(texture, rect_to_rl(source), rect_to_rl(rect), origin, 0, color_to_rl(tint))
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

// @todo(viktor): make clickable, background, text, shadow, border and such all flags with a default behaviour 

begin_ui_element :: proc (size: v2) -> ^Element {
    result := make_ui_element()
    
    result.size      = size
    result.size_kind = .Fixed
    
    return result
}

begin_ui_element_calculated :: proc () -> ^Element {
    result := make_ui_element()
    result.size_kind = .Calculated
    
    return result
}

make_ui_element :: proc () -> ^Element {
    parent := ui_peek_parent()
    
    index := len(the_ui.elements)
    append_nothing(&the_ui.elements)
    result := &the_ui.elements[index]
    result^ = {}
    
    result.parent = parent
    
    return result
}

////////////////////////////////////////////////

begin_horizontal :: proc () {
    result := begin_ui_element_calculated()
    result.flags += { .grow_horizontal }
    result.spacing = 10
    
    ui_push_parent(result)
}

end_horizontal :: proc () {
    element := ui_pop_parent()
    end_ui_element(element)
}

begin_vertical :: proc () {
    result := begin_ui_element_calculated()
    result.spacing = 10
    
    ui_push_parent(result)
}

end_vertical :: proc () {
    element := ui_pop_parent()
    end_ui_element(element)
}

////////////////////////////////////////////////

ui_push_parent :: proc (parent: ^Element) {
    append(&parent_stack, parent)
}

ui_pop_parent :: proc () -> ^Element {
    result := pop(&parent_stack)
    return result
}

ui_peek_parent :: proc (loc := #caller_location) -> ^Element {
    assert(len(parent_stack) > 0, loc = loc)
    result := parent_stack[len(parent_stack) - 1]
    return result
}

////////////////////////////////////////////////

// @api should .interaction just be a maybe, even if we already have a .flags?
ui_element_interaction :: proc (element: ^Element, interaction: Interaction) {
    element.flags      += { .has_interaction }
    element.interaction = interaction
}

ui_element_border :: proc (element: ^Element, color := Red) {
    element.flags += { .has_border }
    element.theme.border = color
}
ui_element_background :: proc (element: ^Element, color: v4) {
    element.flags += { .has_background }
    element.theme.background = color
}
ui_element_text :: proc (element: ^Element, text, shadow: v4, format: string, args: ..any) {
    element.text = tprint(format, ..args)
    element.flags += { .has_text }
    element.theme.text = text
    element.theme.shadow = shadow
}

ui_element_min :: proc (element: ^Element) -> v2 {
    if element == nil do return 0
    
    result: v2
    switch element.size_kind {
    case .Fixed:     result = ui_element_min(element.parent)
    case .Allocated: result = element.bounds.min
        
    case .Calculated:
        result = ui_element_min(element.parent)
        result += element.child_offset
        result += element.padding
        mask := .grow_horizontal in element.flags ? v2{ 1, 0 } : v2{ 0, 1 }
        result += element.spacing * element.child_count * mask
    }
    
    if .has_border in element.flags {
        result += Border_Size
    }
    
    return result
}

Border_Size :: 2

calculate_size :: proc (element: ^Element) -> v2 {
    size: v2
            
    for link := element.first_child; link != nil; link = link.next_child {
        sum_mask := .grow_horizontal in element.flags ? v2{1, 0} : {0, 1}
        max_mask := .grow_horizontal in element.flags ? v2{0, 1} : {1, 0}
        
        if link != element.first_child {
            size += element.spacing * sum_mask
        }
        
        sum_delta := rect_get_dimension(link.bounds)
        max_delta := vec_max(size, sum_delta) - size
        
        size += sum_delta * sum_mask
        size += max_delta * max_mask
    }
    
    size += element.padding * 2
    
    return size
}

end_ui_element :: proc (element: ^Element) {
    // @todo(viktor): resize interactions
    
    border: v2
    if .has_border in element.flags {
        border = Border_Size
    }
    
    parent := element.parent
    
    total_min := ui_element_min(parent)
    
    element.next_child = parent.first_child
    parent.first_child = element
    parent.child_count += 1
    
    element_dim: v2
    switch element.size_kind {
        case .Allocated:  unimplemented()
        case .Fixed:      element_dim = element.size + element.padding * 2
        case .Calculated: element_dim = calculate_size(element)
    }
    
    total_dim := element_dim + border * 2
    total_bounds  := rect_min_dimension(total_min,          total_dim)
    element.bounds = rect_min_dimension(total_min + border, element_dim)
    
    switch parent.size_kind {
    case .Fixed: // nothing
    
    case .Allocated:
        if .grow_horizontal in parent.flags {
            parent.bounds.min.x = total_bounds.max.x
        } else {
            parent.bounds.min.y = total_bounds.max.y
        }
        
    case .Calculated:
        if .grow_horizontal in parent.flags {
            parent.child_offset.x += total_dim.x
        } else {
            parent.child_offset.y += total_dim.y
        }
    }
    
    // @api should this be an extra call, so that this default path can be used, but does not need to happen in this order?
    if .has_border in element.flags {
        draw_rectangle_outline(element.bounds, border, element.theme.border)
    }
    
    if .has_background in element.flags {
        draw_rectangle(element.bounds, element.theme.background)
    }
    
    if .has_text in element.flags {
        // @todo(viktor): should alignment be a parameter?
        text_size := measure_text(the_ui, element.text)
        text_bounds := rect_center_dimension(rect_get_center(element.bounds), text_size)
        draw_text(the_ui, element.text, text_bounds.min, element.theme.text, element.theme.shadow)
    }
    
    // @todo(viktor): maybe move this to end_ui?
    ui := the_ui
    if .has_interaction in element.flags && rect_contains(element.bounds, ui.mouse_p) {
        ui.next_hot_interaction = element.interaction
    }
}

////////////////////////////////////////////////

theme_button :: proc (is_hot: bool, is_active: bool) -> Theme {
    result := theme_default()
    if is_hot {
        result.border = Green
        result.background = Isabelline
        result.text = Green
        result.shadow = 0
    } else if is_active {
        result.background = Green
        result.text = Isabelline
    }
    
    return result
}

theme_dragger :: proc (is_hot_or_active: bool) -> Theme {
    result:= theme_default()
    if is_hot_or_active {
        result.text = Isabelline
    }
    
    return result
}

theme_default :: proc () -> Theme {
    result: Theme
    result.border     = DarkGreen
    result.background = DarkGreen
    result.text       = Jasmine
    result.shadow     = Black
    return result
}