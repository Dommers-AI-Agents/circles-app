        // Extract circle ID from URL
        const pathParts = window.location.pathname.split('/');
        const circleId = pathParts[pathParts.indexOf('circle') + 1];
        
        if (!circleId) {
            showError('Invalid circle link');
        } else {
            loadCircle(circleId);
        }
        
        async function loadCircle(id) {
            try {
                const response = await fetch(`/api/circles/${id}/public`);
                
                if (!response.ok) {
                    if (response.status === 404) {
                        showError('Circle not found');
                    } else if (response.status === 403) {
                        showPrivateCircle();
                    } else {
                        showError('Unable to load circle');
                    }
                    return;
                }
                
                const data = await response.json();
                displayCircle(data);
                
            } catch (error) {
                console.error('Error loading circle:', error);
                showError('Failed to load circle');
            }
        }
        
        function displayCircle(data) {
            const circle = data.circle;
            const places = data.places || [];
            
            // Update meta tags for social sharing
            document.title = `${circle.name} - Circles`;
            updateMetaTags(circle);
            
            const html = `
                <div class="circle-header">
                    <h2 class="circle-title">${escapeHtml(circle.name)}</h2>
                    ${circle.description ? `<p class="circle-description">${escapeHtml(circle.description)}</p>` : ''}
                    <div class="circle-meta">
                        <div class="creator-info">
                            <div class="creator-avatar">
                                ${circle.creatorName ? circle.creatorName.charAt(0).toUpperCase() : 'C'}
                            </div>
                            <span class="creator-name">${escapeHtml(circle.creatorName || 'Anonymous')}</span>
                        </div>
                        <span class="privacy-badge privacy-${circle.privacy}">${circle.privacy}</span>
                        <span class="places-count">${places.length} ${places.length === 1 ? 'place' : 'places'}</span>
                    </div>
                </div>
                
                <div class="cta-buttons">
                    <a href="circles://circle/${circle.id}" class="btn btn-primary">
                        📱 Open in App
                    </a>
                    <button onclick="shareCircle()" class="btn btn-secondary">
                        📤 Share Circle
                    </button>
                </div>
                
                <div class="places-list">
                    ${places.map(place => `
                        <div class="place-card">
                            <div class="place-header">
                                ${place.photoUrl ? `
                                    <img src="${place.photoUrl}" alt="${escapeHtml(place.name)}" class="place-image" onerror="this.style.display='none'">
                                ` : ''}
                                <div class="place-info">
                                    <h3 class="place-name">${escapeHtml(place.name)}</h3>
                                    <p class="place-address">${escapeHtml(place.address || 'No address available')}</p>
                                    ${place.category ? `<span class="place-category">${escapeHtml(place.category)}</span>` : ''}
                                </div>
                            </div>
                            ${place.notes ? `
                                <div class="place-notes">
                                    💭 ${escapeHtml(place.notes)}
                                </div>
                            ` : ''}
                            <div class="place-actions">
                                <a href="https://maps.apple.com/?q=${encodeURIComponent(place.name + ' ' + (place.address || ''))}" 
                                   class="place-action-btn" target="_blank">
                                    🗺️ Apple Maps
                                </a>
                                <a href="https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(place.name + ' ' + (place.address || ''))}" 
                                   class="place-action-btn" target="_blank">
                                    📍 Google Maps
                                </a>
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
            
            document.getElementById('content').innerHTML = html;
        }
        
        function showPrivateCircle() {
            const html = `
                <div class="error-message">
                    <div class="error-icon">🔒</div>
                    <h2>This circle is private</h2>
                    <p style="margin: 20px 0; color: #666;">Download the Circles app and connect with the creator to view this circle.</p>
                    <a href="circles://circle/${circleId}" class="btn btn-primary" style="display: inline-block; margin-top: 20px;">
                        Open in App
                    </a>
                </div>
            `;
            document.getElementById('content').innerHTML = html;
        }
        
        function showError(message) {
            const html = `
                <div class="error-message">
                    <div class="error-icon">⚠️</div>
                    <h2>${message}</h2>
                    <p style="margin: 20px 0; color: #666;">The circle you're looking for might have been removed or the link is invalid.</p>
                    <a href="https://apps.apple.com/us/app/favcircles/id6746807095" class="btn btn-primary" style="display: inline-block; margin-top: 20px;">
                        Download Circles App
                    </a>
                </div>
            `;
            document.getElementById('content').innerHTML = html;
        }
        
        function shareCircle() {
            if (navigator.share) {
                navigator.share({
                    title: document.title,
                    text: 'Check out this circle on Circles!',
                    url: window.location.href
                });
            } else {
                // Fallback: Copy to clipboard
                navigator.clipboard.writeText(window.location.href).then(() => {
                    alert('Link copied to clipboard!');
                });
            }
        }
        
        function escapeHtml(text) {
            if (!text) return '';
            const map = {
                '&': '&amp;',
                '<': '&lt;',
                '>': '&gt;',
                '"': '&quot;',
                "'": '&#039;'
            };
            return text.replace(/[&<>"']/g, m => map[m]);
        }
        
        function updateMetaTags(circle) {
            // Update Open Graph tags
            document.querySelector('meta[property="og:title"]').content = circle.name;
            document.querySelector('meta[property="og:description"]').content = circle.description || 'Discover curated places';
            document.querySelector('meta[property="og:url"]').content = window.location.href;
            
            // Update Twitter Card tags
            document.querySelector('meta[name="twitter:title"]').content = circle.name;
            document.querySelector('meta[name="twitter:description"]').content = circle.description || 'Discover curated places';
        }
