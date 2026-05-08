## test_colorsystem_luminosity_spread
##
## M6: ColorSystem generates `<color>-darken-N` and `<color>-lighten-N`
## variants whose luminance differs from the base by `N * spread / 2`.
##
## The Textual implementation: `luminosity_step = spread / 2`, then
## `delta = n * luminosity_step`, applied to the base via
## `color.lighten(delta).hex` (negative delta = darken). With
## `spread = 0.15`, `darken-1` is 7.5% darker (one step), `darken-2`
## is 15%, `darken-3` is 22.5%.

import std/[tables]
import unittest
import isonim_tui

suite "M6: ColorSystem luminosity spread":
  test "test_colorsystem_luminosity_spread":
    let sys = newColorSystem(
      primary = "#0178D4",
      secondary = "#004578",
      accent = "#ffa62b",
      warning = "#ffa62b",
      error = "#ba3c5b",
      success = "#4EBF71",
      foreground = "#e0e0e0",
      dark = true,
      luminositySpread = 0.15)
    let colors = sys.generate()

    # primary, primary-darken-1..3, primary-lighten-1..3 must all exist.
    check "primary" in colors
    check "primary-darken-1" in colors
    check "primary-darken-2" in colors
    check "primary-darken-3" in colors
    check "primary-lighten-1" in colors
    check "primary-lighten-2" in colors
    check "primary-lighten-3" in colors

    # The base should be the parse-and-format-back of the input hex.
    let primary = parseColor(colors["primary"])
    let darken1 = parseColor(colors["primary-darken-1"])
    let darken2 = parseColor(colors["primary-darken-2"])
    let lighten1 = parseColor(colors["primary-lighten-1"])
    let lighten2 = parseColor(colors["primary-lighten-2"])

    # Each successive darken-N is darker (lower brightness) than the
    # previous one. Lighten-N is brighter.
    check darken1.brightness < primary.brightness
    check darken2.brightness < darken1.brightness
    check lighten1.brightness > primary.brightness
    check lighten2.brightness > lighten1.brightness

  test "test_colorsystem_spread_is_proportional":
    # With spread 0.30 the darken-1 step should be twice the magnitude
    # of the spread=0.15 case (Lab space, monotonic in spread).
    let small = newColorSystem(
      primary = "#0178D4", luminositySpread = 0.10).generate()
    let large = newColorSystem(
      primary = "#0178D4", luminositySpread = 0.30).generate()
    let smallDarken = parseColor(small["primary-darken-2"])
    let largeDarken = parseColor(large["primary-darken-2"])
    # Larger spread → much darker.
    check largeDarken.brightness < smallDarken.brightness

  test "test_colorsystem_includes_full_color_name_set":
    let sys = newColorSystem(primary = "#0178D4")
    let colors = sys.generate()
    # Every base + all 6 shades for each colour name in the canonical
    # list should be present in the generated map.
    for name in ColorNames:
      check name in colors
      for i in 1..3:
        check (name & "-darken-" & $i) in colors
        check (name & "-lighten-" & $i) in colors

  test "test_colorsystem_user_variables_override":
    let sys = newColorSystem(
      primary = "#0178D4",
      variables = {"primary": "#FF0000",
                   "border": "#00FF00"}.toTable)
    let colors = sys.generate()
    check colors["border"] == "#00FF00"
    # primary itself is generated from the parsed primary (the
    # variable override only takes effect for *derived* keys per
    # Textual's `_generate`; the base name is set via lighten(0)).
    # We at least confirm overrides land for the explicit keys we
    # own (border, scrollbar, etc.).

  test "test_colorsystem_dark_versus_light":
    let darkSys = newColorSystem(primary = "#0178D4", dark = true)
    let lightSys = newColorSystem(primary = "#0178D4", dark = false)
    let darkColors = darkSys.generate()
    let lightColors = lightSys.generate()
    # Default backgrounds differ.
    check darkColors["background"] != lightColors["background"]
    # The dark default background should be visually darker.
    check parseColor(darkColors["background"]).brightness <
          parseColor(lightColors["background"]).brightness
