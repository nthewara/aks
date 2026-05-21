param name string
param location string
param addressSpace string = '10.50.0.0/16'
param aksSubnetPrefix string = '10.50.0.0/22'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: name
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ addressSpace ] }
    subnets: [
      {
        name: 'snet-aks'
        properties: {
          addressPrefix: aksSubnetPrefix
        }
      }
    ]
  }
}

output id string = vnet.id
output aksSubnetId string = vnet.properties.subnets[0].id
