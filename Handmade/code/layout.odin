package main

import rl "vendor:raylib"

Layout :: struct {
    dt: f32,
    
    font: rl.Font,
    font_size: f32,
    text_color: rl.Color,
    default_padding: f32,
    
    at:  v2,
    horizontal: bool,
    largest_y_advance: f32,
    base_x: f32,
    
    ////////////////////////////////////////////////
    
    ui: ^UI,
}

////////////////////////////////////////////////

layout_init :: proc (layout: ^Layout, font: rl.Font, text_color: v4, font_size: f32, default_padding: f32 = 8) {
    layout^ = {}
    layout.font = font
    layout.font_size = font_size
    layout.text_color = cast(rl.Color) color_to_u8(text_color)
    layout.default_padding = default_padding
    
    rl.GuiEnable()
    rl.GuiSetFont(layout.font)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiDefaultProperty.TEXT_SIZE, cast(i32) layout.font_size)
    
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

layout_begin :: proc (layout: ^Layout, ui: ^UI, begin: v2, dt: f32) {
    layout.ui = ui
    
    layout.at = begin
    layout.base_x = {}
    layout.horizontal = {}
    layout.largest_y_advance = {}
    layout.dt = dt
}

layout_pad :: proc (layout: ^Layout) {
    layout_advance_2(layout, layout.default_padding)
}
layout_advance :: proc { layout_advance_1, layout_advance_2 }
layout_advance_1 :: proc (layout: ^Layout, size: f32) {
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

@(deferred_in=layout_unindent)
layout_indent_scope :: proc (layout: ^Layout) {
    layout_indent(layout)
}