document.addEventListener('DOMContentLoaded', function() {
  // Enhanced Lightbox functionality
  const gallery = document.querySelector('.screenshot-gallery');
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = lightbox.querySelector('.lightbox-content img');
  const closeBtn = lightbox.querySelector('.lightbox-close');
  const prevBtn = lightbox.querySelector('.lightbox-nav.prev');
  const nextBtn = lightbox.querySelector('.lightbox-nav.next');
  
  let currentImages = [];
  let currentIndex = 0;
  
  if (gallery) {
    // Collect all images in the gallery
    const images = gallery.querySelectorAll('img');
    images.forEach((img, index) => {
      currentImages.push({
        src: img.src,
        alt: img.alt
      });
      
      // Make the figure clickable
      const figure = img.closest('figure');
      if (figure) {
        figure.addEventListener('click', function(e) {
          e.preventDefault();
          currentIndex = index;
          openLightbox();
        });
      }
    });
  }
  
  function openLightbox() {
    if (currentImages.length > 0) {
      updateLightboxImage();
      lightbox.classList.add('active');
      document.body.style.overflow = 'hidden';
    }
  }
  
  function closeLightbox() {
    lightbox.classList.remove('active');
    document.body.style.overflow = '';
  }
  
  function updateLightboxImage() {
    const image = currentImages[currentIndex];
    lightboxImg.src = image.src;
    lightboxImg.alt = image.alt;
    
    // Update navigation buttons visibility
    prevBtn.style.display = currentIndex > 0 ? 'flex' : 'none';
    nextBtn.style.display = currentIndex < currentImages.length - 1 ? 'flex' : 'none';
  }
  
  function navigateImage(direction) {
    if (direction === 'prev' && currentIndex > 0) {
      currentIndex--;
    } else if (direction === 'next' && currentIndex < currentImages.length - 1) {
      currentIndex++;
    }
    updateLightboxImage();
  }
  
  // Event listeners
  if (closeBtn) {
    closeBtn.addEventListener('click', closeLightbox);
  }
  
  if (prevBtn) {
    prevBtn.addEventListener('click', () => navigateImage('prev'));
  }
  
  if (nextBtn) {
    nextBtn.addEventListener('click', () => navigateImage('next'));
  }
  
  // Close on background click
  lightbox.addEventListener('click', function(e) {
    if (e.target === lightbox || e.target.classList.contains('lightbox-content')) {
      closeLightbox();
    }
  });
  
  // Keyboard navigation
  document.addEventListener('keydown', function(e) {
    if (lightbox.classList.contains('active')) {
      if (e.key === 'Escape') closeLightbox();
      if (e.key === 'ArrowLeft') navigateImage('prev');
      if (e.key === 'ArrowRight') navigateImage('next');
    }
  });
  
  // Intersection Observer for lazy loading
  if ('IntersectionObserver' in window && gallery) {
    const imageObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const img = entry.target;
          if (img.dataset.src) {
            img.src = img.dataset.src;
            img.removeAttribute('data-src');
            observer.unobserve(img);
          }
        }
      });
    }, {
      rootMargin: '50px 0px',
      threshold: 0.01
    });
    
    gallery.querySelectorAll('img[data-src]').forEach(img => {
      imageObserver.observe(img);
    });
  }
});