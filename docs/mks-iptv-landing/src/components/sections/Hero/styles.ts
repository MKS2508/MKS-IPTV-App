
export const heroStyles = {
  container: "relative min-h-screen flex items-center justify-center overflow-hidden text-center",
  background: {
    overlay: "absolute inset-0 bg-gradient-to-b from-app-background via-app-surface/80 to-app-background",
    particles: "absolute inset-0 z-0",
  },
  content: {
    wrapper: "relative z-10 max-w-4xl mx-auto px-4 sm:px-6 lg:px-8",
    subtitle: "text-lg md:text-xl mb-2 text-app-highlight font-semibold tracking-wider",
    title: "text-5xl md:text-7xl lg:text-8xl font-bold text-app-text-primary mb-4",
    description: "text-md md:text-lg max-w-2xl mx-auto mb-6 text-app-text-secondary",
    tagline: "text-sm md:text-md font-mono text-app-text-muted mb-8",
    ctaGroup: "flex flex-col sm:flex-row items-center justify-center gap-4",
    cta: {
      primary: "inline-flex items-center justify-center px-8 py-3 bg-app-accent hover:bg-app-accent/90 text-white font-bold rounded-lg transform transition-all duration-300 hover:scale-105 shadow-lg hover:shadow-accent",
      secondary: "inline-flex items-center justify-center px-8 py-3 border-2 border-app-primary hover:border-app-highlight text-app-text-primary hover:text-app-highlight font-semibold rounded-lg transform transition-all duration-300 hover:scale-105",
      tertiary: "text-sm text-app-text-muted hover:text-app-highlight transition-colors duration-200 underline",
    },
  },
  scroll: {
    indicator: "absolute bottom-8 left-1/2 transform -translate-x-1/2 text-app-text-secondary",
    arrow: "w-6 h-6 mx-auto mb-1",
  },
  glow: "text-shadow-[0_0_15px_rgba(255,215,0,0.8)]",
  cssParticles: {
    container: "absolute inset-0 z-0 overflow-hidden",
    particle: "absolute bg-app-accent rounded-full opacity-0",
    animation: "animate-particle-fade-move",
  },
};

export const animationClasses = {
  willChange: "will-change-transform, will-change-opacity",
  subtitle: "hero-subtitle",
  title: "hero-title",
  description: "hero-description",
  tagline: "hero-tagline",
  ctaGroup: "hero-cta-group",
  scrollIndicator: "hero-scroll-indicator",
};
