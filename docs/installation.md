---
layout: default
title: Installation
nav_order: 3
---

<!-- Installation Guide with Platform Tabs -->
<div class="installation-guide">
  <div class="installation-header">
    <h1 class="installation-title">🛠️ Installation Guide</h1>
    <p class="installation-subtitle">Choose your platform and follow the visual step-by-step guide</p>
  </div>

  <!-- Platform Tabs -->
  <div class="platform-tabs">
    <button class="tab-btn active" data-platform="ios">
      <span class="tab-icon">📱</span>
      <span class="tab-label">iOS & iPadOS</span>
    </button>
    <button class="tab-btn" data-platform="macos">
      <span class="tab-icon">💻</span>
      <span class="tab-label">macOS</span>
    </button>
    <button class="tab-btn" data-platform="tvos">
      <span class="tab-icon">📺</span>
      <span class="tab-label">tvOS</span>
    </button>
  </div>

  <!-- iOS Installation -->
  <div class="platform-content active" data-platform="ios">
    <div class="platform-intro">
      <h2>iOS & iPadOS Installation</h2>
      <p>Install using AltStore for the best experience on iPhone and iPad devices.</p>
      
      <div class="requirements-grid">
        <div class="requirement-item">
          <div class="req-icon">📱</div>
          <div class="req-text">iOS 26 Beta or later</div>
        </div>
        <div class="requirement-item">
          <div class="req-icon">💻</div>
          <div class="req-text">Computer with AltServer</div>
        </div>
        <div class="requirement-item">
          <div class="req-icon">📥</div>
          <div class="req-text">Latest IPA file</div>
        </div>
      </div>
    </div>

    <div class="steps-container">
      <div class="step-card">
        <div class="step-number">1</div>
        <div class="step-content">
          <h3>Download the IPA File</h3>
          <p>Get the latest <code>mks-iptv.ipa</code> from our downloads page.</p>
          <a href="download.html" class="step-btn">Download IPA</a>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">📥</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">2</div>
        <div class="step-content">
          <h3>Install with AltStore</h3>
          <p>Open the <code>.ipa</code> file on your iOS device and choose to open it with AltStore.</p>
          <div class="tip">
            <strong>Tip:</strong> Make sure AltStore is installed and running on your device.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">📲</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">3</div>
        <div class="step-content">
          <h3>Trust the Certificate</h3>
          <p>Navigate to <strong>Settings → General → VPN & Device Management</strong> and trust the certificate associated with your Apple ID.</p>
          <div class="warning">
            <strong>Important:</strong> This step is required for the app to launch properly.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">⚙️</div>
        </div>
      </div>
    </div>

    <div class="additional-info">
      <h4>Need More Help?</h4>
      <p>For a detailed walkthrough, check the <a href="https://altstore.io" target="_blank">official AltStore documentation</a> or our <a href="iOS-Free-Installation-Guide.html">comprehensive iOS installation guide</a>.</p>
    </div>
  </div>

  <!-- macOS Installation -->
  <div class="platform-content" data-platform="macos">
    <div class="platform-intro">
      <h2>macOS Installation</h2>
      <p>Simple drag-and-drop installation for Mac computers with Apple Silicon.</p>
      
      <div class="requirements-grid">
        <div class="requirement-item">
          <div class="req-icon">💻</div>
          <div class="req-text">macOS 26 Beta or later</div>
        </div>
        <div class="requirement-item">
          <div class="req-icon">🔥</div>
          <div class="req-text">Apple Silicon (M1/M2/M3)</div>
        </div>
        <div class="requirement-item">
          <div class="req-icon">📦</div>
          <div class="req-text">Latest ZIP file</div>
        </div>
      </div>
    </div>

    <div class="steps-container">
      <div class="step-card">
        <div class="step-number">1</div>
        <div class="step-content">
          <h3>Download the App</h3>
          <p>Get the latest <code>.zip</code> file for Apple Silicon from our downloads page.</p>
          <a href="download.html" class="step-btn">Download for macOS</a>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">📥</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">2</div>
        <div class="step-content">
          <h3>Extract the Application</h3>
          <p>Double-click the downloaded <code>.zip</code> file to extract the application bundle.</p>
          <div class="tip">
            <strong>Tip:</strong> The extraction will create a <code>.app</code> file in your Downloads folder.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">📂</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">3</div>
        <div class="step-content">
          <h3>Move to Applications</h3>
          <p>Drag the <code>MKS-IPTV-App.app</code> file into your <code>/Applications</code> folder.</p>
          <div class="tip">
            <strong>Tip:</strong> You can also press <code>Cmd+Space</code> and search for "Applications" to open the folder.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">📁</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">4</div>
        <div class="step-content">
          <h3>First Launch</h3>
          <p>Right-click the app icon and select "Open". Confirm that you want to run the application when prompted.</p>
          <div class="warning">
            <strong>Security Note:</strong> macOS may warn about an unidentified developer - this is normal for sideloaded apps.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">🚀</div>
        </div>
      </div>
    </div>
  </div>

  <!-- tvOS Installation -->
  <div class="platform-content" data-platform="tvos">
    <div class="platform-intro">
      <h2>tvOS Installation</h2>
      <p>Build and deploy to Apple TV using Xcode. Requires development setup.</p>
      
      <div class="requirements-grid">
        <div class="requirement-item">
          <div class="req-icon">📺</div>
          <div class="req-text">Apple TV (tvOS 26 Beta)</div>
        </div>
        <div class="requirement-item">
          <div class="req-icon">🛠️</div>
          <div class="req-text">Xcode 16 Beta</div>
        </div>
        <div class="requirement-item">
          <div class="req-icon">👨‍💻</div>
          <div class="req-text">Apple Developer Account</div>
        </div>
        <div class="requirement-item">
          <div class="req-icon">🔗</div>
          <div class="req-text">USB-C Cable</div>
        </div>
      </div>
    </div>

    <div class="steps-container">
      <div class="step-card">
        <div class="step-number">1</div>
        <div class="step-content">
          <h3>Clone the Repository</h3>
          <p>Download the source code from GitHub using Terminal:</p>
          <div class="code-block">
            <code>git clone https://github.com/MKS2508/MKS-IPTV-App.git<br>cd MKS-IPTV-App</code>
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">⬇️</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">2</div>
        <div class="step-content">
          <h3>Connect Apple TV</h3>
          <p>Connect your Apple TV to your Mac using a USB-C cable and ensure it's detected.</p>
          <div class="tip">
            <strong>Tip:</strong> Enable Developer Mode on your Apple TV through Settings → System → Software Updates.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">🔌</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">3</div>
        <div class="step-content">
          <h3>Open in Xcode</h3>
          <p>Open the <code>mks-multiplatform-iptv.xcodeproj</code> file in Xcode and configure your signing settings.</p>
          <div class="warning">
            <strong>Important:</strong> Set your Apple Developer Team in the project settings.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">⚙️</div>
        </div>
      </div>

      <div class="step-card">
        <div class="step-number">4</div>
        <div class="step-content">
          <h3>Build and Deploy</h3>
          <p>Select the <code>mks-multiplataforma-tvos-iptv</code> scheme and your Apple TV as the target, then click Run (▶).</p>
          <div class="tip">
            <strong>Tip:</strong> The first build may take several minutes to complete.
          </div>
        </div>
        <div class="step-visual">
          <div class="visual-placeholder">🚀</div>
        </div>
      </div>
    </div>
  </div>

  <!-- Support Section -->
  <div class="support-section">
    <h2>💬 Need Help?</h2>
    <p>If you encounter any issues during installation:</p>
    
    <div class="support-grid">
      <a href="download.html" class="support-item">
        <div class="support-icon">📋</div>
        <div class="support-content">
          <h4>Check Requirements</h4>
          <p>Verify system requirements on the Downloads page</p>
        </div>
      </a>
      
      <a href="https://github.com/MKS2508/MKS-IPTV-App/issues" class="support-item">
        <div class="support-icon">🐛</div>
        <div class="support-content">
          <h4>Report Issues</h4>
          <p>Open an issue on our GitHub repository</p>
        </div>
      </a>
      
      <a href="https://github.com/MKS2508/MKS-IPTV-App/discussions" class="support-item">
        <div class="support-icon">💭</div>
        <div class="support-content">
          <h4>Community Help</h4>
          <p>Start a discussion for general questions</p>
        </div>
      </a>
    </div>
  </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
  // Platform tab switching
  const tabBtns = document.querySelectorAll('.tab-btn');
  const platformContents = document.querySelectorAll('.platform-content');
  
  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const platform = btn.dataset.platform;
      
      // Remove active classes
      tabBtns.forEach(b => b.classList.remove('active'));
      platformContents.forEach(c => c.classList.remove('active'));
      
      // Add active classes
      btn.classList.add('active');
      document.querySelector(`[data-platform="${platform}"].platform-content`).classList.add('active');
    });
  });
  
  // Step card animations
  const stepCards = document.querySelectorAll('.step-card');
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.style.animationPlayState = 'running';
      }
    });
  }, { threshold: 0.1 });
  
  stepCards.forEach(card => {
    card.style.animationPlayState = 'paused';
    observer.observe(card);
  });
});
</script>
