# Firebase Credentials Setup

## After downloading your service account key JSON file:

1. **Rename the file** to `firebase-service-account.json`

2. **Move it to the correct location**:
   ```
   /Users/wesleysgroi/favcircles/backend/config/firebase-service-account.json
   ```

3. **The file should look like this**:
   ```json
   {
     "type": "service_account",
     "project_id": "your-project-id",
     "private_key_id": "abc123...",
     "private_key": "-----BEGIN PRIVATE KEY-----\n...",
     "client_email": "firebase-adminsdk-xyz@your-project.iam.gserviceaccount.com",
     "client_id": "123456789",
     "auth_uri": "https://accounts.google.com/o/oauth2/auth",
     "token_uri": "https://oauth2.googleapis.com/token",
     "auth_provider_x509_cert_url": "https://www.googleapis.com/...",
     "client_x509_cert_url": "https://www.googleapis.com/..."
   }
   ```

4. **Update your .env file** with your project details (next step)