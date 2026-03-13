package main

import "core:fmt"

print :: fmt.printf
sprint :: fmt.aprintf
tprint :: fmt.tprintf
cprint :: fmt.caprintf
ctprint :: fmt.ctprintf

view_magnitude :: proc (#any_int value: u64, precision: u32 = 0) -> string {
    float := cast(f64) value
    if value > 1000_000_000 {
        return tprint("%.*fG", precision, float / 1000_000_000)
    } else if value > 1000_000 {
        return tprint("%.*fM", precision, float / 1000_000)
    } else if value > 1000 {
        return tprint("%.*fk", precision, float / 1000)
    } else {
        return tprint("%.*f",  precision, float)
    }
}

view_percentage :: proc { view_percentage_a, view_percentage_b } 
view_percentage_a :: proc (ratio: $F) -> string {
    return tprint("% 5.2f%%", ratio * 100)
}
view_percentage_b :: proc (#any_int a, b: u64) -> string {
    return view_percentage_a(cast(f64) a / cast(f64) b)
}