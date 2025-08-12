const axios = require('axios');

class OEmbedService {
  constructor() {
    this.providers = {
      tiktok: {
        pattern: /(?:www\.)?tiktok\.com\/@[\w.-]+\/video\/(\d+)/,
        endpoint: 'https://www.tiktok.com/oembed',
        requiresAuth: false
      },
      instagram: {
        pattern: /(?:www\.)?instagram\.com\/(?:p|reel)\/([A-Za-z0-9_-]+)/,
        endpoint: 'https://graph.facebook.com/v18.0/instagram_oembed',
        requiresAuth: true // Requires Facebook app token
      },
      youtube: {
        pattern: /(?:www\.)?(?:youtube\.com\/(?:shorts\/|watch\?v=)|youtu\.be\/)([A-Za-z0-9_-]+)/,
        endpoint: 'https://www.youtube.com/oembed',
        requiresAuth: false
      },
      twitter: {
        pattern: /(?:www\.)?(?:twitter|x)\.com\/\w+\/status\/(\d+)/,
        endpoint: 'https://publish.twitter.com/oembed',
        requiresAuth: false
      }
    };
  }

  /**
   * Detect platform from URL
   */
  detectPlatform(url) {
    for (const [platform, config] of Object.entries(this.providers)) {
      if (config.pattern.test(url)) {
        return platform;
      }
    }
    return null;
  }

  /**
   * Extract video ID from URL
   */
  extractVideoId(url, platform) {
    const config = this.providers[platform];
    if (!config) return null;
    
    const match = url.match(config.pattern);
    return match ? match[1] : null;
  }

  /**
   * Fetch video metadata using oEmbed
   */
  async fetchMetadata(url) {
    try {
      const platform = this.detectPlatform(url);
      if (!platform) {
        throw new Error('Unsupported video platform');
      }

      const config = this.providers[platform];
      let metadata = null;

      switch (platform) {
        case 'tiktok':
          metadata = await this.fetchTikTokMetadata(url, config);
          break;
        case 'instagram':
          metadata = await this.fetchInstagramMetadata(url, config);
          break;
        case 'youtube':
          metadata = await this.fetchYouTubeMetadata(url, config);
          break;
        case 'twitter':
          metadata = await this.fetchTwitterMetadata(url, config);
          break;
        default:
          throw new Error(`Platform ${platform} not implemented`);
      }

      return {
        platform,
        ...metadata,
        originalUrl: url
      };
    } catch (error) {
      console.error('Error fetching video metadata:', error);
      throw error;
    }
  }

  /**
   * Fetch TikTok video metadata
   */
  async fetchTikTokMetadata(url, config) {
    try {
      const response = await axios.get(config.endpoint, {
        params: { url }
      });

      const data = response.data;
      return {
        title: data.title || 'TikTok Video',
        author: data.author_name || 'Unknown',
        authorUrl: data.author_url || '',
        thumbnailUrl: data.thumbnail_url || '',
        embedHtml: data.html || '',
        width: data.width || 325,
        height: data.height || 575,
        duration: null, // TikTok doesn't provide duration via oEmbed
        providerName: 'TikTok',
        providerUrl: 'https://www.tiktok.com'
      };
    } catch (error) {
      console.error('TikTok oEmbed error:', error);
      throw new Error('Failed to fetch TikTok video metadata');
    }
  }

  /**
   * Fetch Instagram video metadata
   */
  async fetchInstagramMetadata(url, config) {
    try {
      // Note: Instagram oEmbed requires Facebook app access token
      // This is a simplified version - in production, you'd need proper auth
      const accessToken = process.env.FACEBOOK_APP_TOKEN;
      
      if (!accessToken) {
        // Fallback to basic metadata
        return {
          title: 'Instagram Reel',
          author: 'Instagram User',
          authorUrl: '',
          thumbnailUrl: '',
          embedHtml: this.generateInstagramEmbed(url),
          width: 326,
          height: 580,
          duration: null,
          providerName: 'Instagram',
          providerUrl: 'https://www.instagram.com'
        };
      }

      const response = await axios.get(config.endpoint, {
        params: {
          url,
          access_token: accessToken,
          fields: 'author_name,thumbnail_url,media_id,html'
        }
      });

      const data = response.data;
      return {
        title: data.title || 'Instagram Reel',
        author: data.author_name || 'Unknown',
        authorUrl: `https://www.instagram.com/${data.author_name}`,
        thumbnailUrl: data.thumbnail_url || '',
        embedHtml: data.html || this.generateInstagramEmbed(url),
        width: data.width || 326,
        height: data.height || 580,
        duration: null,
        providerName: 'Instagram',
        providerUrl: 'https://www.instagram.com'
      };
    } catch (error) {
      console.error('Instagram oEmbed error:', error);
      // Return fallback embed
      return {
        title: 'Instagram Reel',
        author: 'Instagram User',
        authorUrl: '',
        thumbnailUrl: '',
        embedHtml: this.generateInstagramEmbed(url),
        width: 326,
        height: 580,
        duration: null,
        providerName: 'Instagram',
        providerUrl: 'https://www.instagram.com'
      };
    }
  }

  /**
   * Fetch YouTube video metadata
   */
  async fetchYouTubeMetadata(url, config) {
    try {
      const response = await axios.get(config.endpoint, {
        params: {
          url,
          format: 'json',
          maxwidth: 360,
          maxheight: 640
        }
      });

      const data = response.data;
      
      // Extract video ID for thumbnail
      const videoId = this.extractVideoId(url, 'youtube');
      const thumbnailUrl = videoId ? `https://img.youtube.com/vi/${videoId}/maxresdefault.jpg` : data.thumbnail_url;

      return {
        title: data.title || 'YouTube Video',
        author: data.author_name || 'Unknown',
        authorUrl: data.author_url || '',
        thumbnailUrl: thumbnailUrl || '',
        embedHtml: data.html || this.generateYouTubeEmbed(url),
        width: data.width || 360,
        height: data.height || 640,
        duration: null, // Would need YouTube API v3 for duration
        providerName: 'YouTube',
        providerUrl: 'https://www.youtube.com'
      };
    } catch (error) {
      console.error('YouTube oEmbed error:', error);
      throw new Error('Failed to fetch YouTube video metadata');
    }
  }

  /**
   * Fetch Twitter/X video metadata
   */
  async fetchTwitterMetadata(url, config) {
    try {
      const response = await axios.get(config.endpoint, {
        params: {
          url,
          omit_script: true,
          dnt: true
        }
      });

      const data = response.data;
      return {
        title: 'Twitter Video',
        author: data.author_name || 'Twitter User',
        authorUrl: data.author_url || '',
        thumbnailUrl: '', // Twitter doesn't provide thumbnail via oEmbed
        embedHtml: data.html || '',
        width: data.width || 550,
        height: null, // Twitter uses responsive height
        duration: null,
        providerName: 'Twitter',
        providerUrl: 'https://twitter.com'
      };
    } catch (error) {
      console.error('Twitter oEmbed error:', error);
      throw new Error('Failed to fetch Twitter video metadata');
    }
  }

  /**
   * Generate Instagram embed HTML (fallback)
   */
  generateInstagramEmbed(url) {
    return `<blockquote class="instagram-media" data-instgrm-captioned data-instgrm-version="14" style="width:100%;"><a href="${url}" target="_blank">View on Instagram</a></blockquote><script async src="//www.instagram.com/embed.js"></script>`;
  }

  /**
   * Generate YouTube embed HTML (fallback)
   */
  generateYouTubeEmbed(url) {
    const videoId = this.extractVideoId(url, 'youtube');
    if (!videoId) return '';
    
    return `<iframe width="360" height="640" src="https://www.youtube.com/embed/${videoId}" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>`;
  }

  /**
   * Clean and sanitize embed HTML
   */
  sanitizeEmbedHtml(html) {
    // Remove script tags for security (we'll load them separately)
    html = html.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
    
    // Add responsive wrapper classes
    html = html.replace(/width="\d+"/, 'width="100%"');
    html = html.replace(/height="\d+"/, 'height="100%"');
    
    return html;
  }
}

module.exports = new OEmbedService();