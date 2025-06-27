# Health Check and Monitoring Endpoints

## Health Check Endpoint

The backend provides a health check endpoint for monitoring service availability.

### Basic Health Check
```bash
GET /api/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2025-06-27T10:00:00.000Z",
  "service": "circles-backend",
  "version": "1.0.0",
  "environment": "production"
}
```

### Detailed Health Check
```bash
GET /api/health/detailed
```

Response includes:
- Database connectivity status
- Firebase authentication status
- Google Cloud Storage status
- Memory usage
- Uptime

### Usage Examples

#### Command Line
```bash
# Basic health check
curl https://your-service-url.run.app/api/health

# Detailed health check (requires authentication)
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://your-service-url.run.app/api/health/detailed
```

#### Monitoring Script
```bash
#!/bin/bash
# health-check.sh

SERVICE_URL="https://your-service-url.run.app"
ENDPOINT="$SERVICE_URL/api/health"

response=$(curl -s -w "\n%{http_code}" $ENDPOINT)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -eq 200 ]; then
    echo "✅ Service is healthy"
    echo "$body" | jq .
else
    echo "❌ Service is unhealthy (HTTP $http_code)"
    echo "$body"
    exit 1
fi
```

## Google Cloud Monitoring

### Cloud Run Metrics
Monitor these key metrics in the Google Cloud Console:

1. **Request Count**: Total number of requests
2. **Request Latency**: Response time percentiles
3. **Container Instance Count**: Number of running instances
4. **CPU Utilization**: CPU usage percentage
5. **Memory Utilization**: Memory usage percentage

### Setting Up Alerts

1. Go to Cloud Monitoring
2. Create alerting policy
3. Select metric: Cloud Run Revision - Request Count
4. Set condition: Error rate > 5%
5. Configure notification channel

### Uptime Checks

Create an uptime check in Google Cloud:

```bash
gcloud monitoring uptime-checks create circles-health \
  --display-name="Circles Backend Health" \
  --uri="https://your-service-url.run.app/api/health" \
  --check-interval=5m
```

## Logging Queries

### View Recent Errors
```bash
gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=circles-backend \
  AND severity>=ERROR" \
  --limit=50 \
  --format=json
```

### View Slow Requests
```bash
gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=circles-backend \
  AND httpRequest.latency>1s" \
  --limit=20
```

### View Specific User Activity
```bash
gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=circles-backend \
  AND jsonPayload.userId=USER_ID" \
  --limit=100
```

## Performance Monitoring

### Response Time Analysis
```bash
# Get average response time for last hour
gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=circles-backend \
  AND httpRequest.latency!=NULL" \
  --format="value(httpRequest.latency)" \
  --freshness=1h | \
  awk '{sum+=$1; count++} END {print "Average:", sum/count, "seconds"}'
```

### Error Rate Calculation
```bash
# Calculate error rate for last 24 hours
total=$(gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=circles-backend" \
  --format="value(httpRequest.status)" \
  --freshness=24h | wc -l)

errors=$(gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=circles-backend \
  AND httpRequest.status>=500" \
  --format="value(httpRequest.status)" \
  --freshness=24h | wc -l)

echo "Error rate: $(echo "scale=2; $errors * 100 / $total" | bc)%"
```

## Dashboard Creation

Create a custom dashboard in Google Cloud Console:

1. Navigate to Monitoring > Dashboards
2. Create new dashboard
3. Add widgets:
   - Request rate (line chart)
   - Error rate (line chart)
   - Latency percentiles (heatmap)
   - Active instances (gauge)
   - Memory usage (line chart)

## Integration with Third-Party Monitoring

### Datadog Integration
```yaml
# datadog-agent.yaml
logs:
  - type: google_cloud_run
    service: circles-backend
    source: nodejs
```

### New Relic Integration
```javascript
// Add to server.js
if (process.env.NEW_RELIC_LICENSE_KEY) {
  require('newrelic');
}
```

## Troubleshooting Common Issues

### High Latency
1. Check cold start frequency
2. Review database query performance
3. Analyze memory usage patterns
4. Check external API response times

### High Error Rate
1. Review error logs for patterns
2. Check authentication issues
3. Verify environment variables
4. Monitor database connectivity

### Memory Issues
1. Check for memory leaks
2. Review concurrent request handling
3. Optimize large data operations
4. Monitor garbage collection

## Best Practices

1. **Set up alerts** for critical metrics
2. **Regular log reviews** to catch issues early
3. **Performance baselines** to detect anomalies
4. **Automated health checks** every 5 minutes
5. **Dashboard monitoring** during deployments
6. **Error budget tracking** for SLA compliance