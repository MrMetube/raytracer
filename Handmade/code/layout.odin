package main

import "core:math"
import rl "vendor:raylib"

Layout :: struct {
    dt: f32,
    
    font: rl.Font,
    font_size: f32,
    text_color: rl.Color,
    at:  v2,
    
    horizontal: bool,
    largest_y_advance: f32,
    base_x: f32,
}

layout_init :: proc (layout: ^Layout, font: rl.Font, text_color: v4, font_size: f32) {
    layout^ = {}
    layout.font = font
    layout.font_size = font_size
    layout.text_color = cast(rl.Color) color_to_u8(text_color)
    
    rl.GuiEnable()
    rl.GuiSetFont(layout.font)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiDefaultProperty.TEXT_SIZE, cast(i32) layout.font_size)
    
    Background := color_to_u8(DarkGreen)
    Foreground := color_to_u8(Jasmine)
    Highlight  := color_to_u8(Green)
    Focus      := color_to_u8(Isabelline)
    None       := color_to_u8(v4{})
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_NORMAL,     Foreground)
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_NORMAL,     Background)
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_NORMAL,   None)
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_FOCUSED,    Focus)
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_FOCUSED,    Highlight)
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_FOCUSED,  Background)
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_PRESSED,    Highlight)
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_PRESSED,    Focus)
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_PRESSED, Highlight)
    rlGuiSetColor(.DEFAULT, .TEXT_COLOR_DISABLED,   Highlight)
    rlGuiSetColor(.DEFAULT, .BASE_COLOR_DISABLED,   Background)
    rlGuiSetColor(.DEFAULT, .BORDER_COLOR_DISABLED, None)
    
    rlGuiSetColor :: proc (control: rl.GuiControl, property: rl.GuiControlProperty, value: Color) {
        rl.GuiSetStyle(control, auto_cast property, transmute(i32) value.abgr)
    }
}

layout_begin :: proc (layout: ^Layout, begin: v2) {
    layout.at = begin
    layout.base_x = {}
    layout.horizontal = {}
    layout.largest_y_advance = {}
}

layout_advance :: proc (layout: ^Layout, size: f32) {
    if layout.horizontal {
        layout.at.x += size
    } else {
        layout.at.y += size
    }
}

layout_advance_2 :: proc (layout: ^Layout, dimension: v2) {
    if layout.horizontal {
        layout.at.x += dimension.x
        layout.largest_y_advance = max(layout.largest_y_advance, dimension.y)
    } else {
        layout.at.y += dimension.y
    }
}

layout_begin_horizontal :: proc (layout: ^Layout) {
    assert(!layout.horizontal)
    layout.horizontal = true
    
    layout.base_x = layout.at.x
    layout.largest_y_advance = 0
}

layout_end_horizontal :: proc (layout: ^Layout) {
    assert(layout.horizontal)
    layout.horizontal = false
    layout.at.x  = layout.base_x
    layout.at.y += layout.largest_y_advance
}

layout_indent :: proc (layout: ^Layout) {
    layout.at.x += 20
}
layout_unindent :: proc (layout: ^Layout) {
    layout.at.x -= 20
}

////////////////////////////////////////////////

SliderFlag :: enum {
    relative,
    logarithmic,
}
SliderFlags :: bit_set[SliderFlag]

// @copypasta
display_slider_v :: proc (layout: ^Layout, width: f32, value: ^$V/[$N] $E, min: V, max: V, format: string = "", args: ..any, flags := SliderFlags{}) -> bool {
    layout_begin_horizontal(layout)
    if format != "" {
        display_line(layout, format, ..args)
        layout_advance(layout, 10)
    }
    
    slider_width := (width - 20) / len(V)
    result: bool
    for i in 0..<len(V) {
        result ||= display_slider_raw(layout, slider_width, &value[i], min[i], max[i], flags = flags)
        layout_advance(layout, 10)
    }
    layout_end_horizontal(layout)
    
    return result
}

display_slider :: proc { display_slider_f, display_slider_i }
display_slider_i :: proc (layout: ^Layout, width: f32, value: ^$T, min: T, max: T, format: string = "", args: ..any, flags : SliderFlags = {}) -> bool where T != f32 {
    before := value^
    
    slider := cast(f32) value^
    result := display_slider(layout, width, &slider, cast(f32) min, cast(f32) max, format, args = args, flags = flags)
    value^ = round(T, slider)
    
    result &&= value^ != before
    return result
}
display_slider_f :: proc (layout: ^Layout, width: f32, value: ^f32, min: f32, max: f32, format: string = "", args: ..any, flags : SliderFlags = {}) -> bool {
    wrap_horizontal := !layout.horizontal
    if wrap_horizontal do layout_begin_horizontal(layout)
    if format != "" {
        display_line(layout, format, ..args)
        layout_advance(layout, 10)
    }
    
    result := display_slider_raw(layout, width, value, min, max, flags)
    if wrap_horizontal do layout_end_horizontal(layout)
    return result
}

display_slider_raw :: proc (layout: ^Layout, width: f32, value: ^f32, min: f32, max: f32, flags : SliderFlags = {}) -> bool {
    min := min
    max := max
    if .relative in flags {
        min = value^ + (1.0 / min)
        max = value^ + (1.0 / max)
    }
    
    size := v2{width, layout.font_size}
    bounds := rectangle_min_dimension(layout.at, size)
    layout_advance_2(layout, size)
    
    result: bool
    if .logarithmic in flags {
        editing_value := math.ln(value^)
        min = math.ln(min)
        max = math.ln(max)
        rl.GuiSlider(to_rl_rect(bounds), "", "", &editing_value, min, max)
        
        new_value := math.exp(editing_value)
        result = new_value != value^
        value^ = new_value
    } else {
        editing_value := value^
        rl.GuiSlider(to_rl_rect(bounds), "", "", &editing_value, min, max)
        
        result = editing_value != value^
        value^ = editing_value
    }
    
    return result
}

display_line :: proc (layout: ^Layout, format: string, args: ..any) {
    text := ctprint(format, ..args)
    size := rl.MeasureTextEx(layout.font, text, layout.font_size, 1)
    rl.DrawTextEx(layout.font, text, layout.at+2, layout.font_size, 1, rl.BLACK)
    rl.DrawTextEx(layout.font, text, layout.at,   layout.font_size, 1, layout.text_color)
    layout_advance_2(layout, size)
}

display_list :: proc (layout: ^Layout, is_open: ^bool, format: string) -> bool {
    display_toggle(layout, format, is_open)
    return is_open^
}

display_button :: proc (layout: ^Layout, text: string, size := v2{}) -> bool {
    text := ctprint("%v", text)
    size := size
    if size == 0 {
        size = rl.MeasureTextEx(layout.font, text, layout.font_size, 1)
        size.x += 20
    }
    bounds := to_rl_rect(rectangle_min_dimension(layout.at, size))
    result := rl.GuiButton(bounds, text)
    layout_advance_2(layout, size)
    return result
}

display_button_highlighted :: proc (layout: ^Layout, text: string, highlighted: bool, size := v2{}) -> bool {
    condition := highlighted
    display_toggle(layout, text, &condition, size)
    result := condition != highlighted
    return result
}

display_toggle :: proc { display_toggle_bool, display_toggle_condition }
display_toggle_condition :: proc (layout: ^Layout, text: string, condition: bool, size := v2{}) -> (clicked, result: bool) {
    toggle := condition
    clicked = display_toggle(layout, text, &toggle, size)
    return clicked, toggle
}
display_toggle_bool :: proc (layout: ^Layout, text: string, condition: ^bool, size := v2{}) -> bool {
    text := ctprint("%v", text)
    size := size
    if size == 0 {
        size = rl.MeasureTextEx(layout.font, text, layout.font_size, 1)
        size.x += 20
    }
    
    bounds := to_rl_rect(rectangle_min_dimension(layout.at, size))
    
    before := condition^
    rl.GuiToggle(bounds, text, condition)
    result := condition^ != before
    
    layout_advance_2(layout, size)
    
    return result
}
