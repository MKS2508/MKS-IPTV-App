import { ThemeProvider } from "@mks2508/theme-manager-react";
import type { ReactNode } from "react";

interface ThemeProviderProps {
  children?: ReactNode;
  defaultTheme?: string;
  defaultMode?: "light" | "dark" | "auto";
  enableTransitions?: boolean;
}

export function AppThemeProvider({
  children,
  defaultTheme = "synthwave84",
  defaultMode = "auto",
  enableTransitions = true,
}: ThemeProviderProps) {
  return (
    <ThemeProvider
      registryUrl="/registry.json"
      defaultTheme={defaultTheme}
      defaultMode={defaultMode}
      enableTransitions={enableTransitions}
    >
      {children}
    </ThemeProvider>
  );
}
