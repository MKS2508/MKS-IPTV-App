import {
  Button,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@mks2508/mks-ui/react";
import {
  type AnimationPreset,
  type Direction,
  useAnimatedTheme,
} from "@mks2508/theme-manager-react";
import { Download, Palette, Settings } from "lucide-react";

interface IThemeSelectorProps {
  onFontSettings?: () => void;
  onThemeManagement?: () => void;
  animation?: AnimationPreset;
  direction?: Direction;
  duration?: number;
}

/**
 * Dropdown menu for selecting a theme with animated transitions.
 *
 * Now supports spectacular animations via `useAnimatedTheme` hook:
 * - `gif-mask` — Liquid ink/tinta splash with SVG blur
 * - `wipe` — Directional curtain reveal
 * - `circle-expand` — Circle from click point or center
 * - `circle-shrink` — Old state shrinks in circle
 * - `diamond` — Diamond polygon wipe from center
 * - `crossfade` — Simple opacity fade
 * - `slide` — Directional slide + fade
 * - `none` — Instant swap, no animation
 */
function ThemeSelector({
  onFontSettings,
  onThemeManagement,
  animation = "wipe",
  direction = "ltr",
  duration = 500,
}: IThemeSelectorProps) {
  const { currentTheme, themes, setTheme } = useAnimatedTheme({
    animation,
    direction,
    duration,
  });

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="ghost" size="icon" />}>
        <Palette className="size-4" />
        <span className="sr-only">Select theme</span>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="end" className="w-52">
        <DropdownMenuGroup>
          <DropdownMenuLabel>Themes</DropdownMenuLabel>
          <DropdownMenuRadioGroup
            value={currentTheme}
            onValueChange={(value) => void setTheme(value)}
          >
            {themes.map((t) => (
              <DropdownMenuRadioItem key={t.id} value={t.id}>
                <span
                  className="size-3 shrink-0 rounded-full border border-foreground/15"
                  style={{ backgroundColor: t.preview?.primary ?? "currentColor" }}
                />
                {t.label}
              </DropdownMenuRadioItem>
            ))}
          </DropdownMenuRadioGroup>
        </DropdownMenuGroup>

        {(onFontSettings || onThemeManagement) && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              {onFontSettings && (
                <DropdownMenuItem onSelect={onFontSettings}>
                  <Settings className="size-4" />
                  Font Settings
                </DropdownMenuItem>
              )}
              {onThemeManagement && (
                <DropdownMenuItem onSelect={onThemeManagement}>
                  <Download className="size-4" />
                  Manage Themes
                </DropdownMenuItem>
              )}
            </DropdownMenuGroup>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

export { ThemeSelector, type IThemeSelectorProps };
