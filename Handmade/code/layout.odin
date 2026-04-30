package main

layout_begin :: proc (layout: ^Element, bounds: Rectangle2, spacing: f32) {
    layout.bounds = bounds
    layout.flags       = {}
    layout.child_count = {}
    layout.spacing = spacing
}

layout_advance :: proc (layout: ^Element, dimension: v2) {
    layout.bounds.min.y += dimension.y
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