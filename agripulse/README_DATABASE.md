# AgriPulse Database Setup Guide

## Firebase Configuration

### 1. Firebase Project Setup
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create new project: "AgriPulse"
3. Enable **Authentication** → Phone Sign-in
4. Enable **Firestore Database**
5. Enable **Cloud Functions** (for predictions)

### 2. Firestore Security Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Users can read their own predictions and farms
    match /predictions/{predictionId} {
      allow read, write: if request.auth != null && 
        request.auth.uid == resource.data.userId;
    }
    
    match /farms/{farmId} {
      allow read, write: if request.auth != null && 
        request.auth.uid == resource.data.userId;
    }
    
    // Weather data is publicly readable
    match /weather_data/{location} {
      allow read: if true;
      allow write: if request.auth != null;
    }
  }
}
```

### 3. Add Firebase to Flutter
Add to `pubspec.yaml`:
```yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_auth: ^4.16.0
  cloud_firestore: ^4.13.6
  firebase_storage: ^11.5.6
```

### 4. Database Collections Structure

#### Users Collection
```javascript
/users/{userId}
{
  fullName: "John Farmer",
  phone: "+254712345678",
  location: "Nairobi",
  createdAt: timestamp,
  isActive: true,
  farmCount: 2
}
```

#### Predictions Collection
```javascript
/predictions/{predictionId}
{
  userId: "user123",
  cropType: "Maize",
  predictionData: {
    yield: 5.2,
    harvestDate: "2024-03-15",
    risk: "low"
  },
  confidence: 0.85,
  createdAt: timestamp,
  status: "active"
}
```

#### Weather Data Collection
```javascript
/weather_data/{location}
{
  location: "Nairobi",
  weatherInfo: {
    temperature: 25.5,
    humidity: 65,
    rainfall: 12.3,
    forecast: "sunny"
  },
  updatedAt: timestamp
}
```

#### Farms Collection
```javascript
/farms/{farmId}
{
  userId: "user123",
  farmName: "Green Valley Farm",
  size: 2.5,
  location: "Nairobi",
  cropTypes: ["maize", "beans"],
  createdAt: timestamp,
  isActive: true
}
```

## Scalability Features

### 1. Auto-Scaling
- Firebase automatically scales with user growth
- No database maintenance required
- Global CDN for fast access worldwide

### 2. Offline Support
- Data cached locally
- Works in poor connectivity areas
- Syncs when connection restored

### 3. Real-Time Updates
- Live weather updates
- Real-time prediction results
- Instant data synchronization

### 4. Security
- Built-in authentication
- Row-level security rules
- Encrypted data transmission

## Advanced Analytics (Optional)

For complex agricultural analytics, consider:
- **BigQuery** integration with Firebase
- **PostgreSQL** for historical data analysis
- **ML Kit** for on-device predictions

## Cost Optimization

### Free Tier (Firebase)
- 1GB Firestore storage
- 50K document reads/day
- 20K document writes/day
- 10GB download/month

### Scaling Tips
1. Implement data pagination
2. Use efficient queries
3. Cache frequently accessed data
4. Optimize document structure

## Next Steps

1. Set up Firebase project
2. Configure authentication
3. Set up Firestore rules
4. Integrate with Flutter app
5. Test with sample data
