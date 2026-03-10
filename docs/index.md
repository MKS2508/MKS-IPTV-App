---
layout: default
title: Home
nav_order: 1
---

<!-- Professional Three-Stage Hero Section -->
<section class="hero-section immersive-hero">
  <!-- Stage 1: Banner Only (Always Visible) -->
  <div class="hero-background">
    <img src="imgs/banner4.webp" alt="MKS IPTV - Stream. Decode. Rebel." class="hero-banner">
    <div class="hero-overlay"></div>
    <div class="hero-particles" id="particles"></div>
  </div>
  
  <!-- Stage 2: Minimal Glass Header (First Scroll) -->
  <div class="hero-minimal-header" id="minimal-header">
    <div class="minimal-glass-container">
      <div class="hero-brand-inline">
        <img src="assets/imgs/applogo.webp" alt="MKS-IPTV-App" class="logo-minimal">
        <h1 class="title-minimal">MKS-IPTV-App</h1>
      </div>
    </div>
  </div>
  
  <!-- Stage 3: Progressive Element Reveal (Continued Scroll) -->
  <div class="hero-content-progressive" id="progressive-content">
    <!-- Tagline (Appears First) -->
    <div class="hero-element tagline-element" id="tagline-element">
      <p class="hero-tagline-elegant">The Ultimate IPTV Experience for Apple Devices</p>
    </div>
    
    <!-- Download Button (Appears Second) -->
    <div class="hero-element download-element" id="download-element">
      <a href="download.html" class="btn-download-elegant">
        <span class="btn-text">Download Now</span>
        <span class="btn-icon">⬇</span>
      </a>
    </div>
    
    <!-- Badges (Appear Third) -->
    <div class="hero-element badges-element" id="badges-element">
      <div class="hero-badges-elegant">
        <div class="elegant-badge version-badge">
          <span class="badge-icon">🚀</span>
          <span class="badge-text">v1.0-beta</span>
        </div>
        <div class="elegant-badge platform-badge">
          <span class="badge-icon">🍎</span>
          <span class="badge-text">iOS • macOS • tvOS</span>
        </div>
        <div class="elegant-badge swift-badge">
          <span class="badge-icon">⚡</span>
          <span class="badge-text">Swift 6.0</span>
        </div>
      </div>
    </div>
    
    <!-- Platform Buttons (Appear Last) -->
    <div class="hero-element buttons-element" id="buttons-element">
      <div class="platform-buttons-elegant">
        <a href="#features" class="btn-elegant btn-secondary">
          <span class="btn-text">Explore Features</span>
          <span class="btn-icon">✨</span>
        </a>
        <a href="screenshots.html" class="btn-elegant btn-outline">
          <span class="btn-text">View Screenshots</span>
          <span class="btn-icon">📱</span>
        </a>
      </div>
    </div>
  </div>
  
  <!-- Scroll Indicator -->
  <div class="hero-scroll-indicator" id="scroll-indicator">
    <div class="mouse">
      <div class="wheel"></div>
    </div>
    <span class="scroll-text">Scroll to explore</span>
  </div>
</section>

<!-- Screenshot Carousel Section -->
<section class="carousel-section">
  <div class="container">
    <div class="section-header">
      <h2>See It in Action</h2>
      <p>Experience the beautiful interface and powerful features</p>
    </div>
    
    <div class="screenshot-carousel">
      <div class="carousel-container">
        <div class="carousel-track" id="carouselTrack">
          <div class="carousel-slide active">
            <img src="imgs/v0.0.1-alpha/macos/listview_liquidglasstopbar.png" alt="Liquid Glass Navigation" class="carousel-image">
            <div class="carousel-caption">
              <h3>Liquid Glass Design</h3>
              <p>Modern translucent UI patterns from iOS 26</p>
            </div>
          </div>
          <div class="carousel-slide">
            <img src="imgs/v0.0.1-alpha/macos/DownloadsSection_1.png" alt="Download Management" class="carousel-image">
            <div class="carousel-caption">
              <h3>Advanced Downloads</h3>
              <p>Real-time progress tracking and queue management</p>
            </div>
          </div>
          <div class="carousel-slide">
            <img src="imgs/v0.0.1-alpha/macos/seriesdetail_1.png" alt="Series Detail View" class="carousel-image">
            <div class="carousel-caption">
              <h3>Rich Content Views</h3>
              <p>Comprehensive series and episode management</p>
            </div>
          </div>
          <div class="carousel-slide">
            <img src="imgs/v0.0.1-alpha/macos/download_modal.png" alt="Download Configuration" class="carousel-image">
            <div class="carousel-caption">
              <h3>Flexible Configuration</h3>
              <p>Customizable download settings and formats</p>
            </div>
          </div>
        </div>
        
        <!-- Carousel Navigation -->
        <button class="carousel-nav prev" id="carouselPrev" aria-label="Previous screenshot">‹</button>
        <button class="carousel-nav next" id="carouselNext" aria-label="Next screenshot">›</button>
        
        <!-- Carousel Dots -->
        <div class="carousel-dots" id="carouselDots">
          <button class="dot active" data-slide="0" aria-label="Screenshot 1"></button>
          <button class="dot" data-slide="1" aria-label="Screenshot 2"></button>
          <button class="dot" data-slide="2" aria-label="Screenshot 3"></button>
          <button class="dot" data-slide="3" aria-label="Screenshot 4"></button>
        </div>
      </div>
    </div>
  </div>
</section>

---

## 🗺️ Quick Navigation

| | |
| :--- | :--- |
| 📥 [**Downloads**](download.html) | Get the latest builds for all platforms. |
| 🛠️ [**Installation Guide**](installation.html) | Step-by-step instructions to get you started. |
| 📸 [**Screenshots**](screenshots.html) | A visual tour of the app's features. |
| 🐙 [**GitHub Repository**](https://github.com/MKS2508/MKS-IPTV-App) | View the project source and contribute. |

---

## ✨ Core Features {#features}

<div class="features-grid">
  <div class="feature-card fade-in-up" data-delay="100">
    <div class="feature-icon">🍎</div>
    <h3>Native Apple Experience</h3>
    <p>Built with Swift 6 & SwiftUI for optimal performance and seamless integration with the Apple ecosystem.</p>
  </div>
  
  <div class="feature-card fade-in-up" data-delay="200">
    <div class="feature-icon">📺</div>
    <h3>Live TV & VOD</h3>
    <p>Stream your favorite live channels, movies, and series with adaptive quality and minimal buffering.</p>
  </div>
  
  <div class="feature-card fade-in-up" data-delay="300">
    <div class="feature-icon">📥</div>
    <h3>Advanced Downloads</h3>
    <p>Download content for offline viewing with real-time progress tracking and queue management.</p>
  </div>
  
  <div class="feature-card fade-in-up" data-delay="400">
    <div class="feature-icon">🎨</div>
    <h3>Liquid Glass Design</h3>
    <p>Experience the cutting-edge UI patterns from iOS 26 with beautiful translucency and fluid animations.</p>
  </div>
  
  <div class="feature-card fade-in-up" data-delay="500">
    <div class="feature-icon">💻</div>
    <h3>Multi-platform</h3>
    <p>Works seamlessly across iOS, macOS, and tvOS with platform-specific optimizations.</p>
  </div>
  
  <div class="feature-card fade-in-up" data-delay="600">
    <div class="feature-icon">🚀</div>
    <h3>High Performance</h3>
    <p>Optimized streaming with HTTP proxy servers and hardware acceleration for smooth playback.</p>
  </div>
</div>

---

## 💬 Support

Need help? Have a question or a feature request?

- 🐛 [**Report an Issue**](https://github.com/MKS2508/MKS-IPTV-App/issues)
- 💡 [**Start a Discussion**](https://github.com/MKS2508/MKS-IPTV-App/discussions)
- 👨‍💻 [**Contact Developer**](https://github.com/MKS2508)