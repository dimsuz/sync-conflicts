package main

import "core:fmt"
import "core:encoding/xml"
import "core:os"
import "core:mem"
import "core:strings"
import "core:path/filepath"
import "core:c/libc"

walk :: proc (info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Errno, skip_dir: bool) {
  conflicts := (^[dynamic]os.File_Info)(user_data)
  if strings.contains(info.name, "sync-conflict-") {
    append(conflicts, info)
  }
  return in_err, false
}

read_boolean_answer :: proc(prompt: string) -> (answer: bool, err: os.Errno) {
  fmt.printf("%s ", prompt)
  buf: [64]byte
  n, read_err := os.read(os.stdin, buf[:])
  if read_err < 0 {
    return false, read_err
  }
  answer_str := strings.trim_space(string(buf[:n]))
  return len(answer_str) == 0 || answer_str == "\n" || answer_str == "Y" || answer_str == "y", os.ERROR_NONE
}

original_file :: proc(path: string) -> (res: string, err: mem.Allocator_Error) {
  pred :: proc(r: rune) -> bool {
    return r == '.'
  }
  fields := strings.fields_proc(path, pred) or_return
  fields_mod : [dynamic]string
  for f in fields {
    if !strings.contains(f, "sync-conflict") {
      append(&fields_mod, f)
    }
  }
  res = strings.join(fields_mod[:], ".") or_return
  return
}

launch_meld :: proc(original_file: string, conflict_file: string) {
  libc.system(strings.unsafe_string_to_cstring(fmt.aprintf("/usr/bin/meld %s %s", original_file, conflict_file)))
}

main :: proc () {
  file, ok := os.read_entire_file_from_filename("/home/dima/.config/syncthing/config.xml")
  if !ok {
    fmt.eprintln("failed to read syncthing config")
    return
  }
  defer delete(file)
  doc, parse_err := xml.parse_bytes(file)
  if (parse_err != .None) {
    fmt.eprintln("failed to parse config xml")
    return
  }
  defer xml.destroy(doc)
  configuration_tag_eid : u32
  conflicts := make([dynamic]os.File_Info)
  for e, index in doc.elements {
    switch e.ident {
    case "configuration":
      configuration_tag_eid = u32(index)
    case "folder":
      if e.parent == configuration_tag_eid {
        label: string
        path: string
        for a in e.attribs {
          if (a.key == "path") {
            path = a.val
          }
          if (a.key == "label") {
            label = a.val
          }
        }
        if len(path) > 0 && len(label) > 0 {
          fmt.eprintf("Checking \"%s\" folder for conflicts... ", label)
          clear(&conflicts)
          filepath.walk(path, walk, &conflicts)
          if len(conflicts) > 0 {
            fmt.eprintln("FOUND")
            yes, launch_err := read_boolean_answer("  Launch \"meld\"? [Y/n]")
            if launch_err < 0 {
              fmt.eprintln("failed to read answer, ignoring")
            } else if (yes) {
              for c in conflicts {
                orig_file, err := original_file(c.fullpath)
                assert(err == .None)
                launch_meld(orig_file, c.fullpath)
                yes, resolved_err := read_boolean_answer("  Conflicts resolved? [Y/n]")
                if resolved_err < 0 {
                  fmt.eprintln("failed to read answer, keeping conflicts file")
                } else if (yes) {
                  remove_err := os.remove(c.fullpath)
                  if (remove_err != os.ERROR_NONE) {
                    fmt.eprintln("failed to read answer, keeping conflicts file")
                  }
                }
              }
            }
          } else {
            fmt.eprintln("✓ none")
          }
        }
      }
    }
  }
}
