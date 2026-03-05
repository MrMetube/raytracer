package main

import "core:math"
import rl "vendor:raylib"

Layout :: struct {
    font: rl.Font,
    text_color: rl.Color,
    at:  v2,
    
    horizontal: bool,
    largest_y_advance: f32,
    base_x: f32,
}

layout_init :: proc (layout: ^Layout, font: rl.Font, text_color: v4, begin: v2) {
    layout^ = {}
    layout.font = font
    layout.text_color = cast(rl.Color) color_to_u8(text_color)
    layout.at = begin
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

display_slider :: proc (layout: ^Layout, width: f32, value: ^f32, min: f32, max: f32, format: string = "", args: ..any, flags : SliderFlags = {}) -> bool {
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
    
    size := v2{width, FontSize}
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
    size := rl.MeasureTextEx(layout.font, text, FontSize, 1)
    rl.DrawTextEx(layout.font, text, layout.at+2, FontSize, 1, rl.BLACK)
    rl.DrawTextEx(layout.font, text, layout.at, FontSize, 1, layout.text_color)
    layout_advance_2(layout, size)
}

display_list :: proc (layout: ^Layout, is_open: ^bool, format: string) -> bool {
    display_toggle(layout, format, is_open)
    return is_open^
}

display_button :: proc (layout: ^Layout, text: string, size := v2{}) -> bool {
    text := ctprint("%", text)
    size := size
    if size == 0 {
        size = rl.MeasureTextEx(layout.font, text, FontSize, 1)
        size.x += 20
    }
    bounds := to_rl_rect(rectangle_min_dimension(layout.at, size))
    result := rl.GuiButton(bounds, text)
    layout_advance_2(layout, size)
    return result
}

display_toggle :: proc (layout: ^Layout, text: string, condition: ^bool, size := v2{}) -> bool {
    text := ctprint("%", text)
    size := size
    if size == 0 {
        size = rl.MeasureTextEx(layout.font, text, FontSize, 1)
        size.x += 20
    }
    bounds := to_rl_rect(rectangle_min_dimension(layout.at, size))
    result := rl.GuiToggle(bounds, text, condition)
    layout_advance_2(layout, size)
    return result
}
