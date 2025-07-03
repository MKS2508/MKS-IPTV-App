// Enhanced page interactions
document.addEventListener('DOMContentLoaded', function() {
  // Smooth scroll with offset for sticky header
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      e.preventDefault();
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        const headerOffset = 80;
        const elementPosition = target.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - headerOffset;
        
        window.scrollTo({
          top: offsetPosition,
          behavior: 'smooth'
        });
      }
    });
  });
  
  // Enhanced scroll animations
  const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -100px 0px'
  };
  
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
      }
    });
  }, observerOptions);
  
  // Observe all content sections
  document.querySelectorAll('.content-section').forEach(section => {
    observer.observe(section);
  });
  
  // Enhanced mobile navigation
  const navToggle = document.querySelector('.nav-toggle');
  const navMenu = document.querySelector('.nav-menu');
  
  if (navToggle && navMenu) {
    navToggle.addEventListener('click', () => {
      navMenu.classList.toggle('active');
      navToggle.classList.toggle('active');
      document.body.classList.toggle('menu-open');
    });
    
    // Close menu when clicking on links
    document.querySelectorAll('.nav-link').forEach(link => {
      link.addEventListener('click', () => {
        navMenu.classList.remove('active');
        navToggle.classList.remove('active');
        document.body.classList.remove('menu-open');
      });
    });
  }
  
  // Search functionality (placeholder)
  const searchBtn = document.querySelector('.search-btn');
  if (searchBtn) {
    searchBtn.addEventListener('click', () => {
      // Future: Implement search functionality
      console.log('Search functionality coming soon...');
    });
  }
  
  
  
  // Professional Three-Stage Hero Animation System
  const header = document.querySelector('.sticky-header');
  const isHomepage = document.body.classList.contains('homepage');
  const heroScrollIndicator = document.querySelector('#scroll-indicator');
  
  // New hero elements
  const minimalHeader = document.getElementById('minimal-header');
  const progressiveContent = document.getElementById('progressive-content');
  const heroElements = {
    tagline: document.getElementById('tagline-element'),
    download: document.getElementById('download-element'),
    badges: document.getElementById('badges-element'),
    buttons: document.getElementById('buttons-element')
  };

  let lastScrollY = window.pageYOffset;
  let headerVisible = false;
  let stage2Revealed = false;
  let stage3Elements = {
    tagline: false,
    download: false,
    badges: false,
    buttons: false
  };

  function handleProfessionalHeroScroll() {
    const scrollY = window.pageYOffset;
    const viewportHeight = window.innerHeight;
    const scrollProgress = scrollY / viewportHeight;

    // Stage 1: Hide scroll indicator on first scroll
    if (heroScrollIndicator) {
      if (scrollY > viewportHeight * 0.05) { // 5vh scroll
        heroScrollIndicator.style.opacity = '0';
        heroScrollIndicator.style.visibility = 'hidden';
      } else {
        heroScrollIndicator.style.opacity = '1';
        heroScrollIndicator.style.visibility = 'visible';
      }
    }

    // Stage 2: Show minimal glass header after more scroll
    const stage2Trigger = viewportHeight * 0.15; // 15vh scroll
    if (!stage2Revealed && scrollY > stage2Trigger) {
      stage2Revealed = true;
      if (minimalHeader) {
        minimalHeader.classList.add('stage-visible');
      }
      
      // Stage 3: Progressive reveal with staggered timing
      setTimeout(() => {
        if (heroElements.tagline) {
          heroElements.tagline.classList.add('element-visible');
        }
      }, 200);
      
      setTimeout(() => {
        if (heroElements.download) {
          heroElements.download.classList.add('element-visible');
        }
      }, 400);
      
      setTimeout(() => {
        if (heroElements.badges) {
          heroElements.badges.classList.add('element-visible');
        }
      }, 600);
      
      setTimeout(() => {
        if (heroElements.buttons) {
          heroElements.buttons.classList.add('element-visible');
        }
      }, 800);
    }

    // Dynamic header behavior (only on homepage)
    if (isHomepage && scrollProgress >= 0.9) {
      const scrollDirection = scrollY > lastScrollY ? 'down' : 'up';

      if (scrollDirection === 'down' && !headerVisible) {
        headerVisible = true;
        if (header) {
          header.style.transform = 'translateY(0)';
          header.style.opacity = '1';
          header.style.visibility = 'visible';
          header.classList.add('scrolled');
        }
      } else if (scrollDirection === 'up' && scrollY > viewportHeight * 0.5) {
        headerVisible = false;
        if (header) {
          header.style.transform = 'translateY(-100%)';
          header.style.opacity = '0';
        }
      }
    }

    // Enhanced parallax effects for particles only
    const particles = document.getElementById('particles');
    if (particles && scrollY < viewportHeight * 2) {
      const rate = scrollY * -0.2;
      particles.style.transform = `translateY(${rate}px) scale(${1 + scrollY * 0.0001})`;
    }

    // Gentle parallax for minimal header
    if (minimalHeader && scrollY < viewportHeight && stage2Revealed) {
      const headerParallax = scrollY * 0.05;
      minimalHeader.style.transform = `translate(-50%, -50%) translateY(${headerParallax}px)`;
    }

    // Gradual banner fade out starting at 150vh
    const heroBackground = document.querySelector('.immersive-hero .hero-background');
    const bannerFadeStart = viewportHeight * 1.5; // 150vh
    const bannerFadeEnd = viewportHeight * 1.8; // 180vh
    
    if (heroBackground && scrollY > bannerFadeStart) {
      const fadeProgress = Math.min(1, (scrollY - bannerFadeStart) / (bannerFadeEnd - bannerFadeStart));
      heroBackground.style.opacity = 1 - fadeProgress;
      
      if (fadeProgress >= 1) {
        heroBackground.classList.add('banner-fading');
      } else {
        heroBackground.classList.remove('banner-fading');
      }
    } else if (heroBackground) {
      heroBackground.style.opacity = 1;
      heroBackground.classList.remove('banner-fading');
    }

    // Show carousel only after hero is complete (180vh scroll)
    const carouselTrigger = viewportHeight * 1.8; // 180vh
    const screenshotCarousel = document.querySelector('.screenshot-carousel');
    if (screenshotCarousel && scrollY > carouselTrigger) {
      screenshotCarousel.classList.add('carousel-visible');
    }

    lastScrollY = scrollY;
  }
  
  // Smooth scroll behavior
  function smoothScrollTo(target, duration = 1000) {
    const targetPosition = target.getBoundingClientRect().top + window.pageYOffset - 80;
    const startPosition = window.pageYOffset;
    const distance = targetPosition - startPosition;
    let startTime = null;
    
    function animation(currentTime) {
      if (startTime === null) startTime = currentTime;
      const timeElapsed = currentTime - startTime;
      const run = easeInOutQuad(timeElapsed, startPosition, distance, duration);
      window.scrollTo(0, run);
      if (timeElapsed < duration) requestAnimationFrame(animation);
    }
    
    function easeInOutQuad(t, b, c, d) {
      t /= d / 2;
      if (t < 1) return c / 2 * t * t + b;
      t--;
      return -c / 2 * (t * (t - 2) - 1) + b;
    }
    
    requestAnimationFrame(animation);
  }
  
  // Enhanced scroll listeners with performance optimization
  let ticking = false;
  function requestTick() {
    if (!ticking) {
      requestAnimationFrame(handleProfessionalHeroScroll);
      ticking = true;
      setTimeout(() => { ticking = false; }, 16);
    }
  }
  
  window.addEventListener('scroll', requestTick, { passive: true });
  
  // Initialize on load
  handleProfessionalHeroScroll();
  
  // Initialize professional hero system on page load
  if (isHomepage) {
    // Ensure elements start in hidden state
    if (minimalHeader) {
      minimalHeader.classList.remove('stage-visible');
    }
    
    Object.values(heroElements).forEach(element => {
      if (element) {
        element.classList.remove('element-visible');
      }
    });
    
    // If user refreshes at scroll position, trigger appropriate stages
    const currentViewportHeight = window.innerHeight;
    const currentScrollY = window.pageYOffset;
    
    if (currentScrollY > currentViewportHeight * 0.8) {
      stage2Revealed = true;
      if (minimalHeader) {
        minimalHeader.classList.add('stage-visible');
      }
      // Immediately show all stage 3 elements if already scrolled
      Object.keys(heroElements).forEach(key => {
        if (heroElements[key]) {
          heroElements[key].classList.add('element-visible');
        }
      });
    }
    
    // Show carousel if already past trigger point
    if (currentScrollY > currentViewportHeight * 1.8) {
      const screenshotCarousel = document.querySelector('.screenshot-carousel');
      if (screenshotCarousel) {
        screenshotCarousel.classList.add('carousel-visible');
      }
    }
  }
  
  // Professional particle system for enhanced ambiance
  function initProfessionalParticles() {
    const particlesContainer = document.getElementById('particles');
    if (!particlesContainer || !isHomepage) return;
    
    // Clear existing particles
    particlesContainer.innerHTML = '';
    
    // Create subtle floating particles
    const particleCount = window.innerWidth < 768 ? 15 : 25;
    
    for (let i = 0; i < particleCount; i++) {
      const particle = document.createElement('div');
      particle.className = 'particle';
      
      // Random positioning
      particle.style.left = Math.random() * 100 + '%';
      particle.style.animationDelay = Math.random() * 20 + 's';
      particle.style.animationDuration = (Math.random() * 10 + 15) + 's';
      
      // Varied sizes and opacity
      const size = Math.random() * 3 + 2;
      particle.style.width = size + 'px';
      particle.style.height = size + 'px';
      particle.style.opacity = Math.random() * 0.6 + 0.2;
      
      particlesContainer.appendChild(particle);
    }
  }
  
  // Initialize particles on load
  if (isHomepage) {
    initProfessionalParticles();
    
    // Reinitialize particles on resize
    window.addEventListener('resize', () => {
      clearTimeout(window.particleResizeTimeout);
      window.particleResizeTimeout = setTimeout(initProfessionalParticles, 300);
    });
  }
  
  // Platform Tabs System (for Screenshots page)
  const platformTabs = document.querySelectorAll('.tab-btn');
  const platformContents = document.querySelectorAll('.platform-content');
  
  platformTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const platform = tab.dataset.platform;
      
      // Remove active class from all tabs and contents
      platformTabs.forEach(t => t.classList.remove('active'));
      platformContents.forEach(c => c.classList.remove('active'));
      
      // Add active class to clicked tab and corresponding content
      tab.classList.add('active');
      const targetContent = document.getElementById(`${platform}-content`);
      if (targetContent) {
        targetContent.classList.add('active');
      }
    });
  });
  
  // Enhanced Gallery Lightbox
  const galleryItems = document.querySelectorAll('.gallery-item');
  const lightbox = document.getElementById('lightbox');
  
  if (galleryItems.length > 0 && lightbox) {
    galleryItems.forEach((item, index) => {
      const expandBtn = item.querySelector('.gallery-expand');
      const img = item.querySelector('img');
      
      function openGalleryLightbox() {
        const lightboxImg = lightbox.querySelector('.lightbox-content img');
        if (lightboxImg && img) {
          lightboxImg.src = img.src;
          lightboxImg.alt = img.alt;
          lightbox.classList.add('active');
          document.body.style.overflow = 'hidden';
        }
      }
      
      if (expandBtn) {
        expandBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          openGalleryLightbox();
        });
      }
      
      // Also open on image click
      if (img) {
        img.addEventListener('click', openGalleryLightbox);
      }
    });
  }
  
  // Enhanced Back to Top Button
  const backToTopBtn = document.querySelector('.back-to-top');
  
  function updateBackToTopVisibility() {
    if (window.pageYOffset > 300) {
      backToTopBtn.classList.add('visible');
    } else {
      backToTopBtn.classList.remove('visible');
    }
  }
  
  if (backToTopBtn) {
    backToTopBtn.addEventListener('click', (e) => {
      e.preventDefault();
      window.scrollTo({
        top: 0,
        behavior: 'smooth'
      });
    });
    
    window.addEventListener('scroll', updateBackToTopVisibility);
    updateBackToTopVisibility(); // Initial check
  }
});