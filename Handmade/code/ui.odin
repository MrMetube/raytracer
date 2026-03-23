package main

import rl "vendor:raylib"

Drag_Interaction :: struct {
    dragged: bool,
    offset:  v2,
    
    p: v2,
}

display_drag_handle :: proc (layout: ^Layout, drag: ^Drag_Interaction, size: v2) -> bool {
    rect := rectangle_min_dimension(drag.p, size)
    
    if rl.IsMouseButtonPressed(.LEFT) {
        if rectangle_contains(rect, rl.GetMousePosition()) {
            drag.offset = drag.p - rl.GetMousePosition()
            drag.dragged = true
        }
    }
    if rl.IsMouseButtonReleased(.LEFT) {
        drag.dragged = false
    }
    
    if drag.dragged {
        drag.p = rl.GetMousePosition() + drag.offset
    }
    
    handle := rectangle_min_dimension(drag.p, size)
    draw_rectangle_outline(handle, 1, Black)
    draw_rectangle(handle, Isabelline)
    
    return drag.dragged
}

////////////////////////////////////////////////

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