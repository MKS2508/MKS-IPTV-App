import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CornerBracket,
} from "@mks2508/mks-ui/react";
import { type IAnimationSettings, SettingsModal } from "@mks2508/theme-manager-react";
import {
  ChevronRight,
  Flame,
  LayoutDashboard,
  Rocket,
  Settings,
  Terminal,
  Zap,
} from "lucide-react";
import { useState } from "react";
import { ThemeTogglerButton } from "@/components/animate-ui/components/buttons/theme-toggler";
import ClickSpark from "@/components/ClickSpark";
import Counter from "@/components/Counter";
import ShinyText from "@/components/ShinyText";
import { ThemeSelector } from "@/components/ThemeSelector";

// Template variables - replaced by scaffolder
// In dev mode, show friendly placeholders; in production, scaffolder replaces these
const PROJECT_TITLE = import.meta.env.DEV ? "BaseUI Starter" : "Mks Iptv Client";
const DESCRIPTION = import.meta.env.DEV
  ? "A modern React starter template with BaseUI, Vite 8, and Tailwind CSS v4."
  : "log viewer and iptv client player for debug and testing purposes. maybe a future iptv client web";

export function App() {
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [count, setCount] = useState(0);
  const [animationSettings, setAnimationSettings] = useState<IAnimationSettings>({
    preset: "wipe",
    direction: "ltr",
    duration: 500,
  });

  return (
    <ClickSpark sparkColor="#f97316" sparkCount={12} sparkRadius={35} sparkSize={12} duration={600}>
      <div className="min-h-screen bg-background text-foreground grain-overlay tech-grid">
        {/* Header */}
        <header className="sticky top-0 z-50 w-full border-b border-border/50 glass">
          <div className="container flex h-16 items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="relative flex size-8 items-center justify-center rounded-lg bg-primary/10 border border-primary/20">
                <Terminal className="size-4 text-primary" />
                <div className="absolute -top-0.5 -right-0.5 size-2 rounded-full bg-primary animate-pulse" />
              </div>
              <h1 className="font-mono-emphasis text-lg uppercase tracking-wider">
                {PROJECT_TITLE}
              </h1>
              <Badge variant="outline" className="font-mono text-xs">
                v1.0.0
              </Badge>
            </div>

            <div className="flex items-center gap-2">
              <ThemeSelector
                animation={animationSettings.preset}
                direction={animationSettings.direction}
                duration={animationSettings.duration}
              />
              <ThemeTogglerButton
                variant="ghost"
                animation={animationSettings.preset}
                direction={animationSettings.direction}
                duration={animationSettings.duration}
              />
              <Button variant="outline" size="icon" onClick={() => setSettingsOpen(true)}>
                <Settings className="size-4" />
              </Button>
            </div>
          </div>
        </header>

        <main className="container py-16">
          {/* Hero Section */}
          <section className="mb-20 text-center">
            <div className="font-mono text-sm text-muted-foreground mb-4">
              // React 19 + Vite 8 + Tailwind v4
            </div>

            <h2 className="font-mono text-4xl md:text-5xl font-bold tracking-tight mb-4">
              Build faster.
              <br />
              <span className="text-primary">Ship cleaner.</span>
            </h2>

            <p className="text-muted-foreground text-lg mb-8 max-w-2xl mx-auto">{DESCRIPTION}</p>

            <div className="flex justify-center gap-4">
              <Button size="lg" className="font-mono-emphasis">
                <Rocket className="size-4" />
                Get Started
              </Button>
              <Button variant="outline" size="lg" className="font-mono-emphasis">
                View Source
                <ChevronRight className="size-4" />
              </Button>
            </div>
          </section>

          {/* HMR Demo */}
          <section className="mb-16 flex justify-center">
            <Card className="glass border-border/50">
              <CardContent className="p-8 flex flex-col items-center gap-4">
                <p className="font-mono text-sm text-muted-foreground">
                  Edit src/App.tsx and save to test HMR
                </p>
                <Counter
                  value={count}
                  fontSize={48}
                  fontWeight={600}
                  textColor="hsl(var(--primary))"
                  gradientFrom="hsl(var(--background))"
                  gradientTo="transparent"
                />
                <Button
                  variant="outline"
                  size="lg"
                  onClick={() => setCount((c) => c + 1)}
                  className="font-mono-emphasis"
                >
                  Increment
                </Button>
              </CardContent>
            </Card>
          </section>

          {/* Feature Cards */}
          <section className="mb-16">
            <div className="grid md:grid-cols-3 gap-6">
              <FeatureCard
                icon={<Zap className="size-5 text-primary" />}
                title="Modern Stack"
                description="React 19, Vite 8, Tailwind v4, BaseUI"
              />
              <FeatureCard
                icon={<LayoutDashboard className="size-5 text-primary" />}
                title="Component Library"
                description="25+ animated components with StyleSlots"
              />
              <FeatureCard
                icon={<Flame className="size-5 text-primary" />}
                title="Theme System"
                description="Animated transitions, multiple presets"
              />
            </div>
          </section>

          {/* Tech Stack */}
          <section className="text-center">
            <div className="flex flex-wrap justify-center gap-3">
              <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
                <svg className="size-3.5" viewBox="0 0 24 24" fill="#61DAFB">
                  <path d="M12 9.861a2.139 2.139 0 100 4.278 2.139 2.139 0 100-4.278zm-5.992 6.394l-.472-.12C2.018 15.246 0 13.737 0 11.996s2.018-3.25 5.536-4.139l.472-.119.133.468a23.53 23.53 0 001.363 3.578l.101.213-.101.213a23.307 23.307 0 00-1.363 3.578l-.133.467zM5.317 8.95c-2.674.751-4.315 1.9-4.315 3.046 0 1.145 1.641 2.294 4.315 3.046a24.95 24.95 0 011.182-3.046A24.752 24.752 0 015.317 8.95zm12.675 7.305l-.133-.469a23.357 23.357 0 00-1.364-3.577l-.101-.213.101-.213a23.42 23.42 0 001.364-3.578l.133-.468.473.119c3.517.889 5.535 2.398 5.535 4.14s-2.018 3.25-5.535 4.139l-.473.12zm-.491-4.259c.48 1.039.877 2.06 1.182 3.046 2.675-.752 4.315-1.901 4.315-3.046 0-1.146-1.641-2.294-4.315-3.046a24.788 24.788 0 01-1.182 3.046z" />
                  <path d="M5.31 8.945l-.133-.467C4.188 4.992 4.488 2.494 6 1.622c1.483-.856 3.864.155 6.359 2.716l.34.349-.34.349a23.552 23.552 0 00-2.422 2.967l-.135.193-.235.02a23.657 23.657 0 00-3.785.61l-.472.119zm1.896-6.63c-.268 0-.505.058-.705.173-.994.573-1.17 2.565-.485 5.253a25.122 25.122 0 012.912-.475 25.088 25.088 0 012.055-2.544c-1.56-1.519-3.037-2.407-3.777-2.407zm10.589 20.362c-.001 0-.001 0 0 0-1.425 0-3.255-1.073-5.154-3.023l-.34-.349.34-.349a23.53 23.53 0 002.421-2.968l.135-.193.234-.02a23.63 23.63 0 003.787-.609l.472-.119.134.468c.987 3.484.688 5.983-.824 6.854a2.38 2.38 0 01-1.205.308zm-4.096-3.381c1.56 1.519 3.037 2.407 3.777 2.407h.001c.267 0 .505-.058.704-.173.994-.573 1.171-2.566.485-5.254a25.02 25.02 0 01-2.912.475 24.856 24.856 0 01-2.055 2.545zM18.69 8.945l-.472-.119a23.479 23.479 0 00-3.787-.61l-.234-.02-.135-.193a23.414 23.414 0 00-2.421-2.967l-.34-.349.34-.349C14.135 1.778 16.515.767 18 1.622c1.512.872 1.812 3.37.824 6.855l-.134.468zM14.75 7.24c1.142.104 2.227.273 3.224.506.686-2.688.509-4.68-.485-5.253-.988-.571-2.845.304-4.794 2.2A25.088 25.088 0 0114.75 7.24zM7.206 22.677A2.38 2.38 0 016 22.369c-1.512-.871-1.812-3.369-.823-6.854l.132-.468.472.119c1.155.291 2.429.496 3.785.609l.235.02.134.193a23.596 23.596 0 002.422 2.968l.34.349-.34.349c-1.898 1.95-3.728 3.023-5.151 3.023zm-1.19-6.427c-.686 2.688-.509 4.681.485 5.254.987.563 2.843-.305 4.793-2.2a24.998 24.998 0 01-1.855-2.545 24.976 24.976 0 01-2.912-.475l-.511-.034zm5.984.628c-.823 0-1.669-.036-2.516-.106l-.235-.02-.135-.193a30.388 30.388 0 01-1.35-2.122 30.354 30.354 0 01-1.166-2.228l-.1-.213.1-.213a30.3 30.3 0 011.166-2.228c.414-.716.869-1.43 1.35-2.122l.135-.193.235-.02a29.785 29.785 0 015.033 0l.234.02.134.193a30.006 30.006 0 012.517 4.35l.101.213-.101.213a29.6 29.6 0 01-2.517 4.35l-.134.193-.234.02c-.847.07-1.694.106-2.517.106zm-2.197-1.084c1.48.111 2.914.111 4.395 0a29.006 29.006 0 002.196-3.798 28.585 28.585 0 00-2.197-3.798 29.031 29.031 0 00-4.394 0 28.477 28.477 0 00-2.197 3.798 29.114 29.114 0 002.197 3.798z" />
                </svg>
                <span className="font-mono text-xs">React</span>
              </Badge>
              <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
                <img src="/vite.svg" alt="Vite" className="size-3.5" />
                <span className="font-mono text-xs">Vite</span>
              </Badge>
              <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
                <img src="/Tailwind CSS.svg" alt="Tailwind" className="size-3.5" />
                <span className="font-mono text-xs">Tailwind</span>
              </Badge>
              <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
                <img src="/TypeScript.svg" alt="TypeScript" className="size-3.5" />
                <span className="font-mono text-xs">TypeScript</span>
              </Badge>
              <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
                <img src="/Bun.svg" alt="Bun" className="size-3.5" />
                <span className="font-mono text-xs">Bun</span>
              </Badge>
              <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
                <svg className="size-3.5" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M24 12.014c0-.28-.024-.56-.072-.834L12 12l11.928-.819c.048.275.072.553.072.834zM12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm0 1.5c5.799 0 10.5 4.701 10.5 10.5S17.799 22.5 12 22.5 1.5 17.799 1.5 12 6.201 1.5 12 1.5z" />
                </svg>
                <span className="font-mono text-xs">Shadcn</span>
              </Badge>
            </div>
          </section>
        </main>

        {/* Footer */}
        <footer className="border-t border-border/50 py-6">
          <div className="container flex items-center justify-center">
            <a
              href="https://www.npmjs.com/package/@mks2508/mks-ui"
              target="_blank"
              rel="noopener noreferrer"
              className="font-mono text-xs hover:text-primary transition-colors"
            >
              <ShinyText
                text="Made with @mks2508/mks-ui"
                speed={3}
                className="text-muted-foreground"
              />
            </a>
          </div>
        </footer>

        <SettingsModal
          open={settingsOpen}
          onOpenChange={setSettingsOpen}
          initialTab="themes"
          animationSettings={animationSettings}
          onAnimationSettingsChange={setAnimationSettings}
        />
      </div>
    </ClickSpark>
  );
}

/**
 * Feature card with corner brackets and glassmorphism
 */
function FeatureCard({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
}) {
  return (
    <Card className="relative glass isolate rounded-xl border border-border/50 overflow-hidden group hover:border-primary/30 transition-colors">
      <CornerBracket position="tl" variant="default" size={20} />
      <CornerBracket position="br" variant="default" size={20} />
      <CardHeader>
        <div className="flex items-center gap-3">
          <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10 group-hover:bg-primary/20 transition-colors">
            {icon}
          </div>
          <CardTitle className="font-mono-emphasis text-sm uppercase tracking-wider">
            {title}
          </CardTitle>
        </div>
      </CardHeader>
      <CardContent>
        <p className="text-sm text-muted-foreground">{description}</p>
      </CardContent>
    </Card>
  );
}

export default App;
