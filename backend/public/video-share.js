// Landing page for shared moment links (/share/video/:videoId).
// CSP disallows inline scripts, so this lives in its own file like circle-share.js.
(async function () {
    const APP_STORE_URL = 'https://apps.apple.com/us/app/favcircles/id6746807095';
    const content = document.getElementById('content');

    const parts = window.location.pathname.split('/').filter(Boolean); // share, video, :id
    const videoId = parts[parts.length - 1];

    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));

    const showUnavailable = () => {
        content.innerHTML = `
            <div class="unavailable">
                <div class="emoji">🎬</div>
                <h2>This moment is no longer available</h2>
                <p>It may have been removed by the person who shared it.</p>
                <a href="${APP_STORE_URL}" class="btn btn-primary">Get Circles on the App Store</a>
            </div>`;
    };

    try {
        const response = await fetch(`/api/videos/${encodeURIComponent(videoId)}/share-info`);
        if (!response.ok) { showUnavailable(); return; }
        const body = await response.json();
        if (!body.success) { showUnavailable(); return; }

        const v = body.data;
        const title = v.title || (v.placeName ? `A moment at ${v.placeName}` : 'A moment on Circles');
        const metaBits = [];
        if (v.userDisplayName) metaBits.push(`Shared by ${v.userDisplayName}`);
        if (v.placeName) metaBits.push(v.placeName);

        const thumb = v.thumbnailUrl
            ? `<div class="thumb-wrap">
                   <img src="${esc(v.thumbnailUrl)}" alt="Moment preview">
                   <div class="play-badge">&#9654;</div>
               </div>`
            : '';

        content.innerHTML = `
            ${thumb}
            <div class="moment-info">
                <div class="moment-title">${esc(title)}</div>
                <div class="moment-meta">${esc(metaBits.join(' · '))}</div>
                <a href="circles://video/${encodeURIComponent(videoId)}" class="btn btn-primary">Watch in Circles</a>
                <a href="${APP_STORE_URL}" class="btn btn-secondary">Get the app</a>
            </div>`;

        document.title = `${title} - Circles`;
    } catch (e) {
        showUnavailable();
    }
})();
