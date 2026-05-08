## isonim_tui/widgets.nim — Tier-1a widget set (M11).
##
## Single point of import for the foundational widget primitives that
## every interactive widget in M12+ sits inside. Re-exports every
## public symbol from the per-widget modules so callers can write
## `import isonim_tui/widgets` and access `newStatic`, `newLabel`,
## `newContainer`, `newPlaceholder`, `newRule` without hunting for
## the right submodule.

import widgets/borders
import widgets/static as staticMod
import widgets/label as labelMod
import widgets/container as containerMod
import widgets/placeholder as placeholderMod
import widgets/rule as ruleMod
import widgets/button as buttonMod
import widgets/switch as switchMod
import widgets/checkbox as checkboxMod
import widgets/radio_button as radioButtonMod
import widgets/radio_set as radioSetMod
import widgets/input as inputMod
import widgets/tabs as tabsMod
import widgets/content_switcher as contentSwitcherMod
import widgets/tabbed_content as tabbedContentMod
import widgets/listview as listViewMod
import widgets/option_list as optionListMod
import widgets/modal as modalMod
import widgets/collapsible as collapsibleMod
import widgets/toast as toastMod
import widgets/loading_indicator as loadingIndicatorMod
import widgets/select as selectMod
import widgets/image as imageMod

export borders
export staticMod
export labelMod
export containerMod
export placeholderMod
export ruleMod
export buttonMod
export switchMod
export checkboxMod
export radioButtonMod
export radioSetMod
export inputMod
export tabsMod
export contentSwitcherMod
export tabbedContentMod
export listViewMod
export optionListMod
export modalMod
export collapsibleMod
export toastMod
export loadingIndicatorMod
export selectMod
export imageMod
