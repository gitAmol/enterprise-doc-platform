// ============================================================================
// Enterprise Document Processing Platform - Main Infrastructure
// ============================================================================
// Author: [Your Name]
// Description: Event-driven, AI-powered document processing platform
// ============================================================================

targetScope = 'subscription'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for deployment')
param location string = 'eastus'

@description('Project name prefix')
param projectName string = 'docplatform'

@description('Tags for all resources')
param tags object = {
  Project: 'Enterprise-Doc-Platform'
  Environment: environment
  ManagedBy: 'Bicep'
}

// Generate unique suffix for globally unique names (8 chars to keep names short)
var uniqueSuffix = take(uniqueString(subscription().subscriptionId, projectName, environment), 8)
var resourceGroupName = 'rg-${projectName}-${environment}'

// ============================================================================
// Resource Group
// ============================================================================
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Module Deployments
// ============================================================================

// 1. Key Vault - Secrets Management (Deploy First)
module keyVault 'modules/keyvault.bicep' = {
  scope: rg
  name: 'keyVault-deployment'
  params: {
    keyVaultName: 'kv${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// 2. Storage Account - Document Storage
module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage-deployment'
  params: {
    storageAccountName: 'st${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// 3. Cosmos DB - Metadata Store
module cosmosDb 'modules/cosmosdb.bicep' = {
  scope: rg
  name: 'cosmosdb-deployment'
  params: {
    accountName: 'cosmos${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// 4. Service Bus - Message Queue
module serviceBus 'modules/servicebus.bicep' = {
  scope: rg
  name: 'servicebus-deployment'
  params: {
    namespaceName: 'sb${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// 5. Azure AI Services - Document Intelligence & OpenAI
module aiServices 'modules/ai-services.bicep' = {
  scope: rg
  name: 'ai-services-deployment'
  params: {
    aiServicesName: 'ai${uniqueSuffix}'
    openAiName: 'oai${uniqueSuffix}'
    searchServiceName: 'srch${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// 6. Azure Functions - Processing Engine
module functions 'modules/functions.bicep' = {
  scope: rg
  name: 'functions-deployment'
  params: {
    functionAppName: 'func${uniqueSuffix}'
    location: location
    tags: tags
    storageAccountName: storage.outputs.storageAccountName
    keyVaultName: keyVault.outputs.keyVaultName
    serviceBusNamespace: serviceBus.outputs.namespaceName
    cosmosDbAccountName: cosmosDb.outputs.accountName
  }
}

// 7. API Management - Skipped, deploy manually from portal
// module apim 'modules/apim.bicep' = {
//   scope: rg
//   name: 'apim-deployment'
//   params: {
//     apimName: 'apim${uniqueSuffix}'
//     location: location
//     tags: tags
//     functionAppName: functions.outputs.functionAppName
//   }
// }

// 8. Monitoring - Application Insights & Log Analytics
module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring-deployment'
  params: {
    logAnalyticsName: 'log${uniqueSuffix}'
    appInsightsName: 'appi${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================
output resourceGroupName string = rg.name
output keyVaultName string = keyVault.outputs.keyVaultName
output storageAccountName string = storage.outputs.storageAccountName
output functionAppName string = functions.outputs.functionAppName
output cosmosDbEndpoint string = cosmosDb.outputs.endpoint
