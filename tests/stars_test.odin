/* [[file:../../../blender.org::*Stars][Stars:1]] */
package stars_test

import "core:mem"
import "core:fmt"
import "core:sync"
import "core:thread"
import "core:math/bits"
import "core:strings"
import "vendor:raylib"
import stars "../"

MAX_INT :: bits.I32_MAX
MENU_RECT :: raylib.Rectangle{250, 10, 240, 150}

draw_menu :: proc(w, h: i32, values: ^stars.Values) {
  using raylib

  menu_rect := MENU_RECT
  menu_rect.x = f32(w) - menu_rect.x
  if !values.show_menu {
    values.show_menu = GuiButton(Rectangle{f32(w) - 40, 13, 18, 18}, "_")
  } else {
    panel := GuiPanel(menu_rect, "")
    values.show_menu = !GuiButton(Rectangle{f32(w) - 40, 13, 18, 18}, "_")

    tmp_brightness := values.brightness_factor
    GuiSlider(Rectangle{f32(w) - 185, 40, 160, 20}, "brightness", "", &tmp_brightness, 5, 150)
    values.brightness_factor = tmp_brightness
    str := fmt.tprintf("%v", values.brightness_factor)
    cstr := strings.clone_to_cstring(str)
    GuiTextBox(Rectangle{f32(w) - 185, 40, 160, 20}, cstr, 10, false)
    delete(cstr)

    tmp_star_range_indices := values.star_range_indices
    GuiSlider(Rectangle{f32(w) - 185, 65, 160, 20}, "randomy", "", &tmp_star_range_indices, 5, 15)
    values.star_range_indices = tmp_star_range_indices
    str = fmt.tprintf("%v", values.star_range_indices)
    cstr = strings.clone_to_cstring(str)
    GuiTextBox(Rectangle{f32(w) - 185, 65, 160, 20}, cstr, 10, false)
    delete(cstr)

    tmp_level_depth := values.level_depth
    GuiSlider(Rectangle{f32(w) - 185, 90, 160, 20}, "depth", "", &tmp_level_depth, 1, 8)
    values.level_depth = tmp_level_depth
    str = fmt.tprintf("%v", values.level_depth)
    cstr = strings.clone_to_cstring(str)
    GuiTextBox(Rectangle{f32(w) - 185, 90, 160, 20}, cstr, 10, false)
    delete(cstr)

    tmp_star_density := values.star_density
    GuiSlider(Rectangle{f32(w) - 185, 115, 160, 20}, "density", "", &tmp_star_density, 1, 2)
    values.star_density = tmp_star_density
    str = fmt.tprintf("%v", values.star_density)
    cstr = strings.clone_to_cstring(str)
    GuiTextBox(Rectangle{f32(w) - 185, 115, 160, 20}, cstr, 10, false)
    delete(cstr)
    
  }
}

main :: proc() {
	using raylib

  ta := mem.Tracking_Allocator{}
  mem.tracking_allocator_init(&ta, context.allocator)
  context.allocator = mem.tracking_allocator(&ta)

  {
    WIDTH  :: 500
    HEIGHT :: 500
    w, h : i32

    values : stars.Values
    values.brightness_factor = 15
    values.star_range_indices = 10
    values.level_depth = 6
    values.star_density = 2

    SetConfigFlags(ConfigFlags{ConfigFlag.WINDOW_RESIZABLE})
    InitWindow(WIDTH, HEIGHT, "Stars Test")
    SetTargetFPS(60)

    s : stars.StarData
    pos := Vector2{0,0}
    scale : f32 = 1
    prev_scale := scale
    s.rect = [4]f32{pos.x, pos.y, WIDTH / scale, HEIGHT / scale}

    star_data_thread := stars.get_stars(&s, &values)

    panning := false
    textColor := LIGHTGRAY
    clicked_pos : Vector2
    delta : Vector2

    for !WindowShouldClose() {
      // Update ------------------------------
      w = GetScreenWidth()
      h = GetScreenHeight()

      // if menu is open and mouse is inside menu don't do this stuff
      d := GetMousePosition()
      menu_rect := MENU_RECT
      menu_rect.x = f32(w) - menu_rect.x
      if !values.show_menu || !raylib.CheckCollisionPointRec(d, menu_rect) {
        if IsMouseButtonPressed(MouseButton.LEFT) && !panning {
          panning = true
          clicked_pos = GetMousePosition()
          textColor = YELLOW
        }
        if IsMouseButtonDown(MouseButton.LEFT) {
          delta.x = (clicked_pos.x - d.x) / scale
          delta.y = (clicked_pos.y - d.y) / scale
          
          // update stars
          sync.lock(&s.mutex)
          s.rect = [4]f32{pos.x + delta.x, pos.y + delta.y, f32(w) / scale, f32(h) / scale}
          sync.unlock(&s.mutex)
          star_data_thread = stars.get_stars(&s, &values)
        } else if panning {
          panning = false
          pos.x += delta.x
          pos.y += delta.y
          delta.x = 0
          delta.y = 0
          textColor = LIGHTGRAY
        }
        
        gmwm : f32 = GetMouseWheelMove()
        if gmwm != 0.0 {
          mult : f32 = (gmwm > 0.5) ? 1.01 : (1 / 1.01)
          scale *= mult // max scale is around 1470656.750, since that*500 is greater than MAX_INT, TODO: is this right?
          if (scale * f32(w) > MAX_INT) || (scale * f32(h) > MAX_INT) {
            scale = prev_scale
          }
          
          e := GetMousePosition()
          pos.x += e.x * (1 - 1 / mult) / scale
          pos.y += e.y * (1 - 1 / mult) / scale
        }
        if scale != prev_scale {
          // update stars
          sync.lock(&s.mutex)
          s.rect = [4]f32{pos.x, pos.y, f32(w) / scale, f32(h) / scale}
          sync.unlock(&s.mutex)
          star_data_thread = stars.get_stars(&s, &values)
          prev_scale = scale
        }
      }
      
      // Draw   ------------------------------
      BeginDrawing()
      ClearBackground(BLACK)
      
      DrawText("Pan: hold left mouse button", 0, 0, 10, textColor)
      str := fmt.tprintf("%.0f %.0f %.3f", pos.x + delta.x, pos.y + delta.y, scale)
      cstr := strings.clone_to_cstring(str)
      DrawText(cstr, 0, 11, 10, textColor)
      DrawText("Zoom: scroll mouse wheel", 0, 22, 10, textColor)
      delete(cstr)
      
      sync.lock(&s.mutex)
      for star in s.stars {
        a : u8 = cast(u8)(star.z * 255)
        x := cast(i32)((star.x - (pos.x + delta.x)) * scale)
        y := cast(i32)((star.y - (pos.y + delta.y)) * scale)
        DrawPixel(x, y, Color{a,a,a,a})
      }
      sync.unlock(&s.mutex)

      draw_menu(w, h, &values)

      EndDrawing()
    }

    CloseWindow()
    
    for ; !thread.is_done(star_data_thread); {}
    free(star_data_thread)
    stars.get_stars(nil, nil) // clean this procs statics
  }

  if len(ta.allocation_map) > 0 {
    for _, v in ta.allocation_map {
      fmt.printf("Leaked %v bytes @ %v\n", v.size, v.location)
    }
  }
  if len(ta.bad_free_array) > 0 {
    fmt.println("Bad frees:");
    for v in ta.bad_free_array {
      fmt.println(v)
    }
  }
}
/* Stars:1 ends here */
