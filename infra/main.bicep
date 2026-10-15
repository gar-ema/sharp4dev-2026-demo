// Infrastruttura della demo APIOps - Sharp4Dev 2026
// Crea UNA istanza APIM (tier Basic v2) per l'ambiente indicato.
// Solo in "dev" viene seminata l'API "orders" con backend, named value e prodotto:
// dev è l'ambiente canonico da cui `apiops extract` produce gli artefatti.
// qa e prod ricevono la configurazione SOLO tramite `apiops publish` (è il punto della demo).

targetScope = 'resourceGroup'

@description('Ambiente: dev | qa | prod')
@allowed(['dev', 'qa', 'prod'])
param env string

@description('Prefisso del nome APIM (deve essere globalmente univoco: <prefix>-<env>)')
param namePrefix string = 'apim-s4d'

@description('Regione')
param location string = resourceGroup().location

@description('Email del publisher (obbligatoria per APIM)')
param publisherEmail string

@description('Nome del publisher')
param publisherName string = 'Sharp4Dev 2026 - APIOps demo'

@description('Se true semina le API demo orders/catalog/genai (solo per l\'ambiente canonico)')
param seedOrdersApi bool = (env == 'dev')

var apimName = '${namePrefix}-${env}'

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
  tags: {
    event: 'sharp4dev-2026'
    env: env
    managedBy: 'apiops-cli'
  }
}

// ---------- Seed (solo dev): la configurazione che poi verrà estratta ----------

resource nvEnvName 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'env-name'
  properties: {
    displayName: 'env-name'
    value: env
    secret: false
  }
}

resource nvOrdersKey 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'orders-backend-key'
  properties: {
    displayName: 'orders-backend-key'
    value: 'dev-secret-key-not-for-prod'
    secret: true // l'extract lo redige: in qa/prod va fornito via override (token o Key Vault)
  }
}

resource backend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'orders-backend'
  properties: {
    title: 'Orders backend'
    description: 'Backend fittizio: la demo usa mock-response, l\'URL serve a mostrare gli override'
    url: 'https://orders-dev.contoso.example'
    protocol: 'http'
  }
}

resource ordersApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'orders'
  properties: {
    displayName: 'Orders API'
    description: 'API demo per APIOps: GET /orders e GET /orders/{id}'
    path: 'orders'
    protocols: ['https']
    apiType: 'http'
    subscriptionRequired: false
    serviceUrl: 'https://orders-dev.contoso.example'
    format: 'openapi'
    value: loadTextContent('orders-openapi.yaml')
  }
}

resource ordersApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = if (seedOrdersApi) {
  parent: ordersApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/orders-api.policy.xml')
  }
}

resource listOrdersPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (seedOrdersApi) {
  name: '${apimName}/orders/list-orders/policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/list-orders.policy.xml')
  }
  dependsOn: [ordersApi]
}

resource getOrderPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (seedOrdersApi) {
  name: '${apimName}/orders/get-order/policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/get-order.policy.xml')
  }
  dependsOn: [ordersApi]
}

resource product 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'sharp4dev'
  properties: {
    displayName: 'Sharp4Dev'
    description: 'Prodotto demo'
    subscriptionRequired: false
    state: 'published'
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = if (seedOrdersApi) {
  parent: product
  name: 'orders'
  dependsOn: [ordersApi]
}


// ---------- Policy fragment condiviso (header standard) ----------

resource fragStdHeaders 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'std-headers'
  properties: {
    description: 'Header standard: X-Request-Id, X-Environment, X-Gateway'
    format: 'rawxml'
    value: loadTextContent('policies/fragment-std-headers.xml')
  }
  dependsOn: [nvEnvName]
}

// ---------- Catalog API: risposte casuali, cache, check-header, choose, CORS ----------

resource catalogBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'catalog-backend'
  properties: {
    title: 'Catalog backend'
    url: 'https://catalog-dev.contoso.example'
    protocol: 'http'
  }
}

resource catalogApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'catalog'
  properties: {
    displayName: 'Catalog API'
    description: 'Catalogo fittizio: prezzi e stock casuali, cache 20s, chaos mode'
    path: 'catalog'
    protocols: ['https']
    apiType: 'http'
    subscriptionRequired: false
    serviceUrl: 'https://catalog-dev.contoso.example'
    format: 'openapi'
    value: loadTextContent('catalog-openapi.yaml')
  }
}

resource catalogApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = if (seedOrdersApi) {
  parent: catalogApi
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/catalog-api.policy.xml') }
  dependsOn: [fragStdHeaders, catalogBackend]
}

resource listProductsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (seedOrdersApi) {
  name: '${apimName}/catalog/list-products/policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/list-products.policy.xml') }
  dependsOn: [catalogApi]
}

resource getPricePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (seedOrdersApi) {
  name: '${apimName}/catalog/get-price/policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/get-price.policy.xml') }
  dependsOn: [catalogApi]
}

// ---------- GenAI API: facciata OpenAI-compatible con llm-token-limit (mock in demo) ----------

resource genaiBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'genai-backend'
  properties: {
    title: 'GenAI backend (Microsoft Foundry / Azure OpenAI)'
    description: 'In demo punta all API genai-mock sullo stesso gateway. In prod: https://<resource>.openai.azure.com/openai'
    url: '${apim.properties.gatewayUrl}/genai-mock'
    protocol: 'http'
  }
}

resource genaiMockApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'genai-mock'
  properties: {
    displayName: 'GenAI mock model'
    description: 'Finto modello OpenAI-compatible: backend di genai in demo'
    path: 'genai-mock'
    protocols: ['https']
    apiType: 'http'
    subscriptionRequired: false
    format: 'openapi'
    value: loadTextContent('genai-mock-openapi.yaml')
  }
}

resource genaiMockApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = if (seedOrdersApi) {
  parent: genaiMockApi
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/genai-mock-api.policy.xml') }
  dependsOn: [nvEnvName]
}

resource genaiApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = if (seedOrdersApi) {
  parent: apim
  name: 'genai'
  properties: {
    displayName: 'GenAI Chat API'
    description: 'Facciata OpenAI-compatible governata dall AI gateway (token limit)'
    path: 'genai'
    protocols: ['https']
    apiType: 'http'
    subscriptionRequired: false
    serviceUrl: 'https://genai-dev.contoso.example/openai'
    format: 'openapi'
    value: loadTextContent('genai-openapi.yaml')
  }
}

resource genaiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = if (seedOrdersApi) {
  parent: genaiApi
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/genai-api.policy.xml') }
  dependsOn: [fragStdHeaders, genaiBackend]
}

resource chatCompletionsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (seedOrdersApi) {
  name: '${apimName}/genai/chat-completions/policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/chat-completions.policy.xml') }
  dependsOn: [genaiApi]
}

resource productApiCatalog 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = if (seedOrdersApi) {
  parent: product
  name: 'catalog'
  dependsOn: [catalogApi]
}

resource productApiGenai 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = if (seedOrdersApi) {
  parent: product
  name: 'genai'
  dependsOn: [genaiApi]
}

output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
