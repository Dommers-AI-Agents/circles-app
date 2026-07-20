        // Get the redirect path from URL parameter
        const urlParams = new URLSearchParams(window.location.search);
        const redirectPath = urlParams.get('path') || 'daily-summary';
        const deepLink = 'circles://' + redirectPath;
        
        // Store whether we've successfully opened the app
        let appOpened = false;
        
        // Function to attempt opening the app
        function attemptAppOpen() {
            // Try to open the app using the custom URL scheme
            window.location.href = deepLink;
            
            // Set a flag that we've attempted to open
            appOpened = true;
            
            // After a delay, check if we're still on this page
            setTimeout(function() {
                // If we're still here, the app probably isn't installed
                if (!document.hidden && appOpened) {
                    showFallback();
                }
            }, 2500);
        }
        
        // Function to show fallback UI
        function showFallback() {
            document.getElementById('loading-state').classList.add('hidden');
            document.getElementById('fallback-state').classList.remove('hidden');
        }
        
        // Set up the manual open button
        document.getElementById('open-app-btn').addEventListener('click', function(e) {
            e.preventDefault();
            window.location.href = deepLink;
            
            // After attempting to open, show download option more prominently
            setTimeout(function() {
                if (!document.hidden) {
                    window.location.href = 'https://apps.apple.com/us/app/favcircles/id6746807095';
                }
            }, 1000);
        });
        
        // Listen for page visibility changes
        document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
                // Page is hidden, app likely opened successfully
                appOpened = true;
            }
        });
        
        // Attempt to open the app immediately
        attemptAppOpen();
        
        // Also try using a hidden iframe as a fallback method
        setTimeout(function() {
            if (!appOpened && !document.hidden) {
                const iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                iframe.src = deepLink;
                document.body.appendChild(iframe);
                
                setTimeout(function() {
                    document.body.removeChild(iframe);
                }, 100);
            }
        }, 500);
