/* [[file:../../blender.org::*Stars][Stars:2]] */
package stars

import "core:fmt"
import "core:sync"
import "core:thread"
import "core:math"
import "core:math/bits"
import "core:strings"

Values :: struct {
  show_menu          : bool,
  brightness_factor  : f32 `15`, // Higher = brighter
  star_range_indices : f32 `10`, // Higher = more random looking, comp expensive
  level_depth        : f32 `6`,  // Higher = more (faint) stars, comp expensive
  star_density       : f32 `2`,  // Higher = more stars (2-3), comp expensive
}

MAX_INT :: bits.I32_MAX

Cache :: distinct map[string][3]f32

StarData :: struct {
  stars : [dynamic][3]f32,
  rect  : [4]f32,
  mutex : sync.Mutex,
}

hashFnv32 :: proc(s : string) -> i32 {
  h : u32 = 0x811c9dc5
  hval : i32 = cast(i32)h

  for i, l := 0, len(s); i < l; i+=1 {
    hval ~=  cast(i32)s[i]
    hval += (hval << 1) + (hval << 4) + (hval << 7) + (hval << 8) +   (hval << 24)
  }
  return hval
}

cached_hash :: proc(to_hash : string, cache : ^Cache = nil) -> [3]f32 {
  if cache != nil {
    if cached, ok := cache[to_hash]; !ok {
      return cached
    }
  }
  a := cast(f32)hashFnv32(strings.concatenate({to_hash, "a"}))
  b := cast(f32)hashFnv32(strings.concatenate({to_hash, "b"}))
  c := cast(f32)hashFnv32(strings.concatenate({to_hash, "c"}))
  digest := [3]f32{ a, b, c }
  if cache != nil {
    cache[to_hash] = digest
  }
  return digest
}

get_stars :: proc(s: ^StarData, values: ^Values) -> ^thread.Thread {
  @static t : ^thread.Thread
  WorkerData :: struct {
    s: ^StarData,
    v: ^Values,
  }
  @static d : ^WorkerData

  if s == nil || values == nil {
    free(d)
    return nil
  }
  if d == nil {
    d = new(WorkerData)
  }
  
  worker :: proc(t: ^thread.Thread) {
    data := t.data
    td := cast(^WorkerData)data
    s := td.s
    values := td.v

    // worker can take some time, so put stars into here, then
    // delete prev stars and set stars to work_stars
    work_stars : [dynamic][3]f32

    sync.lock(&s.mutex)
    rect := s.rect // make a copy
    sync.unlock(&s.mutex)

    // The level at which you would expect one star in current viewport.
    level_for_current_density := - math.log_f32(rect[2] * rect[3], math.E) / values.star_density
    start_level := math.floor_f32(level_for_current_density)

    for level := start_level; level < start_level + values.level_depth; level += 1 {
      spacing := math.exp_f32(-level)
      for
        xIndex := math.floor_f32(rect.x / spacing) - values.star_range_indices;
      xIndex <= math.ceil_f32((rect.x + rect[2]) / spacing) + values.star_range_indices;
      xIndex += 1
      {
        for
          yIndex := math.floor_f32(rect.y / spacing) - values.star_range_indices;
        yIndex <= math.ceil_f32((rect.y + rect[3]) / spacing)	+ values.star_range_indices;
        yIndex += 1
        {
          str := fmt.tprintf("%d:%d:%d", xIndex, yIndex, level)
          hash := cached_hash(str)
    
          e1 := math.exp_f32(level_for_current_density - level - abs(hash.z / MAX_INT))
          e2 := math.exp_f32(level_for_current_density - (start_level + values.level_depth))
          t := math.atan((e1 - e2) * values.brightness_factor) * 2 / math.PI
    
          append(&work_stars, [3]f32{
            xIndex * spacing + (hash.x / MAX_INT) * spacing * values.star_range_indices,
            yIndex * spacing + (hash.y / MAX_INT) * spacing * values.star_range_indices,
            max(0, t)})
        }
      }
    }
    sync.lock(&s.mutex)
    clear(&s.stars)
    for si in work_stars {
      append(&s.stars, si)
    }
    sync.unlock(&s.mutex)
  }

  if t == nil || thread.is_done(t) {
    // creates a new worker thread IF there isn't one already
    if s != nil && values != nil {
      d.s = s
      d.v = values
      if t != nil do free(t)
      t = thread.create(worker)
      t.data = d
      thread.start(t)
    }
  }
  return t
}
/* Stars:2 ends here */
