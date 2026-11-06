// ============================================================================
// Service Bus Module - Enterprise Message Queue with Dead-Letter Support
// ============================================================================

@description('Service Bus namespace name')
param namespaceName string

@description('Location')
param location string

@description('Tags')
param tags object

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'  // Standard for topics, Basic for queues only
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'  // Restrict in production
  }
}

// Queue for document processing
resource documentQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'document-processing'
  properties: {
    maxDeliveryCount: 5
    defaultMessageTimeToLive: 'P1D'  // 1 day
    lockDuration: 'PT5M'             // 5 minutes lock
    deadLetteringOnMessageExpiration: true
    enablePartitioning: false
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
  }
}

// Queue for AI processing
resource aiQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'ai-processing'
  properties: {
    maxDeliveryCount: 3
    defaultMessageTimeToLive: 'P1D'
    lockDuration: 'PT5M'  // Max allowed on Standard tier
    deadLetteringOnMessageExpiration: true
    enablePartitioning: false
  }
}

// Queue for notifications
resource notificationQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'notifications'
  properties: {
    maxDeliveryCount: 10
    defaultMessageTimeToLive: 'PT1H'  // 1 hour
    lockDuration: 'PT1M'
    deadLetteringOnMessageExpiration: true
  }
}

// Topic for document events (pub/sub pattern)
resource documentTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'document-events'
  properties: {
    defaultMessageTimeToLive: 'P1D'
    enablePartitioning: false
    requiresDuplicateDetection: true
  }
}

// Subscription for analytics
resource analyticsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: documentTopic
  name: 'analytics'
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT1M'
  }
}

// Subscription for archival
resource archiveSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: documentTopic
  name: 'archive'
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT1M'
  }
}

output namespaceName string = serviceBusNamespace.name
output namespaceId string = serviceBusNamespace.id
output endpoint string = serviceBusNamespace.properties.serviceBusEndpoint
