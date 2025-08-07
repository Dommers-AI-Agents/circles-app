# POI Analysis with LLM Integration Plan

## Overview
This document outlines a comprehensive plan for implementing cost-effective POI (Point of Interest) analysis using LLM integration for the Circles app. The goal is to analyze user visit history to identify meaningful places, filter out transit/traffic stops, and provide intelligent insights about visit patterns.

## 1. API Cost Comparison

### Apple Maps API (MapKit JS)
- **Free Tier**: 250,000 map views + 25,000 service calls per day
- **Requirements**: Apple Developer Program membership ($99/year)
- **Beyond Free Tier**: $0.50 per 1,000 views (negotiable for enterprise)
- **Advantages**: Very generous free tier, native iOS integration

### Google Places API
- **Free Tier**: $200 monthly credit
- **Pricing**: 
  - Search requests: $2.83 per 1,000 requests
  - Full address/type: $17 per 1,000 requests
  - Contact info: $3 per 1,000 requests
- **Changes**: Legacy APIs deprecated March 2025, pricing increases expected

**Recommendation**: Apple Maps API is significantly more cost-effective for POI analysis

## 2. Offline POI Database Solutions

### OpenStreetMap (OSM) Options

#### Geofabrik Extracts
- Daily updates by region/country
- PBF format, cleaned of sensitive data
- Free to download and use
- Available at: https://download.geofabrik.de/

#### Overpass API
- Query specific POI types
- Can set up local instance
- 180-second query timeout on public servers
- 10,000 queries/day limit on public servers

#### BBBike Extracts
- City-level data (2-50MB)
- Multiple formats available
- Good for smaller geographic areas
- Available at: https://extract.bbbike.org/

### Database Architecture
- **PostgreSQL + PostGIS**: Spatial indexing for geographic queries
- **pgvector**: Vector embeddings for semantic search
- **Combined approach**: Use both for hybrid spatial/semantic POI search

## 3. Self-Hosted LLM Architecture

### LLM Inference Options

#### For Development/Prototyping: Ollama
- Easy setup and management
- GGUF model format
- Good for single-user scenarios
- Lower performance but "good enough" for many use cases
- Simple API interface

#### For Production: vLLM
- 3.23x faster than Ollama with concurrent requests
- PagedAttention for memory efficiency
- Continuous batching for throughput
- Better for multi-user scenarios
- OpenAI-compatible API

### Recommended Models for POI Analysis
1. **TinyLlama-1.1B** (Lightweight)
   - 637 MB when 4-bit quantized
   - Fast inference, low resource usage
   - Good for basic POI categorization

2. **Mistral-7B** (Balanced)
   - ~4GB when quantized
   - Good reasoning capabilities
   - Suitable for pattern analysis

3. **Llama-3.1-8B** (Advanced)
   - ~5GB when quantized
   - Excellent for complex analysis
   - Better context understanding

### Hardware Requirements
- Model size (GB) = Parameters (billions) × 2 + 20% overhead
- Example: 11B model needs ~26.4GB GPU memory
- Consider quantized models (4-bit/8-bit) for reduced memory usage

## 4. Proposed Zero/Low-Cost Architecture

### Phase 1: Minimal Cost POI Analysis
1. Use Apple Maps API free tier (25,000 service calls/day)
2. Cache POI results in PostgreSQL/PostGIS
3. Implement smart caching to minimize API calls
4. Use existing Firebase infrastructure

### Phase 2: Offline POI Enhancement
1. Download regional OSM data via Geofabrik
2. Set up PostgreSQL with PostGIS + pgvector
3. Import POI data with spatial indexing
4. Query local database first, fallback to Apple Maps API

### Phase 3: Self-Hosted LLM Integration
1. Start with Ollama for development
   - Test with smaller models (7B-13B parameters)
   - Use quantized models for efficiency
2. Create API endpoint: Circles → Self-hosted server → LLM analysis
3. Implement caching layer for repeated queries
4. Consider vLLM for production if needed

### Integration Pattern
```
Circles App 
    ↓
Backend API (Node.js on Cloud Run)
    ↓
Query Router
    ├─→ Local OSM Database (PostGIS)
    ├─→ Apple Maps API (fallback)
    └─→ Self-hosted LLM (analysis)
         ├─→ Ollama (dev/low-traffic)
         └─→ vLLM (production/high-traffic)
```

## 5. Visit Analysis Pipeline

### Data Flow
1. **GPS Coordinates Input**
   - Latitude, longitude, accuracy
   - Visit duration, time of day
   - Movement patterns

2. **POI Identification**
   - Query local OSM database (radius search)
   - Fallback to Apple Maps API if needed
   - Cache results for future queries

3. **LLM Analysis**
   - Input: Visit data + POI candidates
   - Process: Categorization, filtering, pattern detection
   - Output: Meaningful place identification, insights

4. **Results Storage**
   - Store analyzed results in Firebase
   - Update visit records with POI data
   - Generate user insights

### Filtering Logic

#### Meaningful Place Criteria
- Dwell time > 5 minutes
- Movement pattern (stationary vs passing through)
- Place category from POI database
- Visit frequency and patterns
- Time of day analysis

#### Traffic/Transit Filtering
- Speed analysis (>25 mph likely in transit)
- Linear movement patterns
- Highway/road proximity detection
- Short dwell times (<2 minutes)
- Multiple quick stops in sequence

## 6. Implementation Roadmap

### Immediate Actions (Week 1-2)
- [ ] Register for Apple Developer Program
- [ ] Implement Apple Maps API integration
- [ ] Add caching layer to minimize API calls
- [ ] Monitor daily usage against free tier limits

### Short-term (Month 1-2)
- [ ] Set up PostgreSQL with PostGIS
- [ ] Download regional OSM data
- [ ] Import POI data with spatial indexing
- [ ] Build hybrid query system
- [ ] Implement basic place categorization

### Medium-term (Month 3-4)
- [ ] Deploy Ollama server for LLM inference
- [ ] Create analysis API endpoints
- [ ] Test POI enrichment with LLM
- [ ] Implement visit pattern analysis
- [ ] Build insight generation system

### Long-term (Month 5+)
- [ ] Evaluate vLLM for production use
- [ ] Implement vector search with pgvector
- [ ] Build comprehensive POI knowledge base
- [ ] Add multi-language support
- [ ] Implement advanced pattern recognition

## 7. Technical Implementation Details

### Backend API Endpoints
```javascript
// New endpoints for POI analysis
POST /api/visits/analyze-batch
  - Batch analyze multiple visits
  - Returns enriched visit data with POI info

GET /api/visits/:id/insights
  - Get AI-generated insights for a visit
  - Includes place category, purpose prediction

POST /api/users/:id/visit-patterns
  - Analyze user's overall visit patterns
  - Returns behavioral insights, frequent places
```

### Database Schema Extensions
```sql
-- POI cache table
CREATE TABLE poi_cache (
  id UUID PRIMARY KEY,
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  name VARCHAR(255),
  category VARCHAR(100),
  subcategory VARCHAR(100),
  address TEXT,
  source VARCHAR(50), -- 'osm', 'apple_maps'
  raw_data JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Spatial index for efficient queries
CREATE INDEX idx_poi_location ON poi_cache 
USING GIST (ST_MakePoint(longitude, latitude));

-- Visit analysis results
CREATE TABLE visit_analysis (
  id UUID PRIMARY KEY,
  visit_id UUID REFERENCES visits(id),
  poi_id UUID REFERENCES poi_cache(id),
  confidence_score DECIMAL(3, 2),
  visit_purpose VARCHAR(100),
  insights TEXT,
  llm_model VARCHAR(50),
  analyzed_at TIMESTAMP DEFAULT NOW()
);
```

### LLM Prompt Templates
```python
# POI Identification Prompt
"""
Analyze this visit data and identify the most likely place visited:

Visit Details:
- Location: {latitude}, {longitude}
- Duration: {duration} minutes
- Time: {visit_time}
- Day: {day_of_week}

Nearby POIs:
{poi_list}

Consider:
1. Visit duration and time of day
2. POI operating hours
3. Typical visit patterns
4. Location accuracy

Return the most likely POI and confidence score (0-1).
"""

# Visit Pattern Analysis Prompt
"""
Analyze these visit patterns for user insights:

Recent Visits:
{visit_history}

Identify:
1. Frequent visit categories
2. Time-based patterns
3. Behavioral insights
4. Recommendations

Format as user-friendly insights.
"""
```

## 8. Privacy and Security Considerations

### Data Privacy
- All location data must be anonymized for LLM processing
- Implement data retention policies
- User consent for AI analysis
- Option to opt-out of analysis

### Security Measures
- Encrypt location data in transit and at rest
- Secure API endpoints with authentication
- Rate limiting for analysis requests
- Audit logs for data access

## 9. Performance Optimization

### Caching Strategy
- Cache POI lookups (24-hour TTL)
- Cache LLM analysis results
- Implement Redis for fast lookups
- Batch process visits during off-peak hours

### Scalability Considerations
- Horizontal scaling for API servers
- Queue system for batch processing
- Database partitioning by geographic region
- CDN for static POI data

## 10. Success Metrics

### Key Performance Indicators
- POI identification accuracy (>85% target)
- Traffic/transit filtering accuracy (>90% target)
- API cost per user (<$0.10/month)
- Analysis latency (<2 seconds)
- User engagement with insights

### User Value Metrics
- Percentage of visits with identified POIs
- Quality of generated insights
- User feedback on accuracy
- Feature adoption rate

## 11. Future Enhancements

### Advanced Features
1. **Predictive Analysis**
   - Predict next likely visits
   - Recommend new places based on patterns

2. **Social Features**
   - Compare visit patterns with friends
   - Discover popular places in network

3. **Business Intelligence**
   - Anonymous aggregated insights
   - Trend analysis for businesses

4. **Multi-modal Analysis**
   - Incorporate photos from visits
   - Weather data correlation
   - Event data integration

### Technology Upgrades
- Implement vector databases for semantic search
- Fine-tune LLM on visit data
- Real-time streaming analysis
- Edge computing for privacy

## Conclusion

This plan provides a comprehensive roadmap for implementing cost-effective POI analysis with LLM integration. By leveraging free tiers, open-source data, and self-hosted infrastructure, the Circles app can provide intelligent visit insights while maintaining low operational costs. The phased approach allows for gradual implementation and validation at each stage.