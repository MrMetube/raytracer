package main

import rl "vendor:raylib"

////////////////////////////////////////////////

layout_init :: proc (layout: ^Element, font: rl.Font, font_size: f32, spacing: f32 = 8) {
    layout^ = {}
    layout.font = font
    layout.font_size = font_size
    layout.spacing = spacing
    
    rl.GuiEnable()
    rl.GuiSetFont(layout.font)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiDefaultProperty.TEXT_SIZE, cast(i32) layout.font_size)
    
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

layout_begin :: proc (layout: ^Element, ui: ^UI, bounds: Rectangle2, dt: f32) {
    layout.ui = ui
    layout.dt = dt
    
    layout.bounds = bounds
    layout.flags       = {}
    layout.child_count = {}
}

layout_advance :: proc (layout: ^Element, dimension: v2) {
    if .grow_horizontal in layout.flags {
        layout.bounds.min.x += dimension.x
    } else {
        layout.bounds.min.y += dimension.y
    }
}

layout_indent :: proc (layout: ^Element) {
    layout.bounds.min.x += 20
}
layout_unindent :: proc (layout: ^Element) {
    layout.bounds.min.x -= 20
}

@(deferred_in=layout_unindent)
layout_indent_scope :: proc (layout: ^Element) {
    layout_indent(layout)
}