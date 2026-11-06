// ============================================================================
// Azure Functions Module - Serverless Processing Engine with Managed Identity
// ============================================================================

@description('Function App name')
param functionAppName string

@description('Location')
param location string

@description('Tags')
param tags object

@description('Storage account name')
param storageAccountName string

@description('Key Vault name')
param keyVaultName string

@description('Service Bus namespace')
param serviceBusNamespace string

@description('Cosmos DB account name')
param cosmosDbAccountName string

// Reference existing resources
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespace
}

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' existing = {
  name: cosmosDbAccountName
}

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-${functionAppName}'
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false  // Windows
  }
}

// Application Insights for Functions
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${functionAppName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
  }
}

// Function App with System-Assigned Managed Identity
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'  // Managed Identity for zero-trust
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      netFrameworkVersion: 'v8.0'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: ['https://portal.azure.com']
      }
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        // Key Vault Reference (Managed Identity)
        {
          name: 'KeyVaultUri'
          value: keyVault.properties.vaultUri
        }
        // Service Bus Connection (Managed Identity)
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: '${serviceBus.name}.servicebus.windows.net'
        }
        // Cosmos DB Connection (Managed Identity)
        {
          name: 'CosmosDbConnection__accountEndpoint'
          value: cosmosDb.properties.documentEndpoint
        }
        // Storage Connection for Blob Trigger (Managed Identity)
        {
          name: 'BlobStorageConnection__blobServiceUri'
          value: storageAccount.properties.primaryEndpoints.blob
        }
      ]
    }
  }
}

// Role Assignments for Managed Identity

// Storage Blob Data Contributor
resource storageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Service Bus Data Sender & Receiver
resource serviceBusSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, functionApp.id, 'Service Bus Data Sender')
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, functionApp.id, 'Service Bus Data Receiver')
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User
resource keyVaultSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output principalId string = functionApp.identity.principalId
