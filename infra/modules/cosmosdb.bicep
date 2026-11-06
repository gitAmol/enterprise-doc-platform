// ============================================================================
// Cosmos DB Module - Serverless Metadata Store
// ============================================================================

@description('Cosmos DB account name')
param accountName string

@description('Location')
param location string

@description('Tags')
param tags object

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      {
        name: 'EnableServerless'  // Serverless for cost optimization
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    enableFreeTier: false
    enableAutomaticFailover: false
    publicNetworkAccess: 'Enabled'  // Restrict in production
  }
}

// Database
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  parent: cosmosAccount
  name: 'DocumentPlatformDB'
  properties: {
    resource: {
      id: 'DocumentPlatformDB'
    }
  }
}

// Container for document metadata
resource documentsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: database
  name: 'Documents'
  properties: {
    resource: {
      id: 'Documents'
      partitionKey: {
        paths: ['/tenantId']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          { path: '/*' }
        ]
        excludedPaths: [
          { path: '/"_etag"/?' }
        ]
      }
      defaultTtl: -1  // No expiration
    }
  }
}

// Container for processing jobs
resource jobsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: database
  name: 'ProcessingJobs'
  properties: {
    resource: {
      id: 'ProcessingJobs'
      partitionKey: {
        paths: ['/status']
        kind: 'Hash'
      }
      defaultTtl: 604800  // 7 days TTL for jobs
    }
  }
}

// Container for audit logs
resource auditContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: database
  name: 'AuditLogs'
  properties: {
    resource: {
      id: 'AuditLogs'
      partitionKey: {
        paths: ['/year']
        kind: 'Hash'
      }
      defaultTtl: 7776000  // 90 days retention
    }
  }
}

output accountName string = cosmosAccount.name
output endpoint string = cosmosAccount.properties.documentEndpoint
output databaseName string = database.name
