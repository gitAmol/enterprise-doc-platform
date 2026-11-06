// ============================================================================
// AI Services Module - Document Intelligence, OpenAI, and AI Search
// ============================================================================

@description('AI Services account name')
param aiServicesName string

@description('OpenAI account name')
param openAiName string

@description('AI Search service name')
param searchServiceName string

@description('Location')
param location string

@description('Tags')
param tags object

// Azure AI Services (Document Intelligence, Vision, Speech, etc.)
resource aiServices 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'CognitiveServices'  // Multi-service account
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Azure OpenAI Service - Skipped due to quota limits, deploy manually from portal
// resource openAi 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
//   name: openAiName
//   location: 'eastus'
//   tags: tags
//   kind: 'OpenAI'
//   sku: {
//     name: 'S0'
//   }
//   properties: {
//     customSubDomainName: openAiName
//     publicNetworkAccess: 'Enabled'
//     networkAcls: {
//       defaultAction: 'Allow'
//     }
//   }
// }

// resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
//   parent: openAi
//   name: 'gpt-4o'
//   sku: {
//     name: 'Standard'
//     capacity: 10
//   }
//   properties: {
//     model: {
//       format: 'OpenAI'
//       name: 'gpt-4o'
//       version: '2024-11-20'
//     }
//     raiPolicyName: 'Microsoft.Default'
//   }
// }

// resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
//   parent: openAi
//   name: 'text-embedding-ada-002'
//   sku: {
//     name: 'Standard'
//     capacity: 30
//   }
//   properties: {
//     model: {
//       format: 'OpenAI'
//       name: 'text-embedding-ada-002'
//       version: '2'
//     }
//   }
//   dependsOn: [gpt4oDeployment]
// }

// Placeholder outputs for OpenAI (will be populated when deployed manually)
var openAiEndpointValue = 'https://${openAiName}.openai.azure.com/'

// Azure AI Search (Cognitive Search)
resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: 'eastus'  // Use eastus for better service availability
  tags: tags
  sku: {
    name: 'basic'  // Basic tier for vector search support
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    semanticSearch: 'free'  // Enable semantic search
  }
}

output aiServicesName string = aiServices.name
output aiServicesEndpoint string = aiServices.properties.endpoint
output openAiName string = openAiName
output openAiEndpoint string = openAiEndpointValue
output searchServiceName string = searchService.name
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'
