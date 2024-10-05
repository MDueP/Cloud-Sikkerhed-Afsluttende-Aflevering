"""
KEA - Cloud-Sikkerhed 3. Semester - The Cloud Case
Lavet af Irem Yilmaz & Mikkel Due-Pedersen
D. 04/10-2024
"""

#RG Variabler
$resourcegroup = 'kea-finalrg'
$location = 'swedencentral'

#Public IP for NAT Gateway
$gwpublicip = @{
    Name = 'myNATgatewayIP'
    ResourceGroupName = $resourcegroup
    Location = $location
    Sku = 'Standard'
    AllocationMethod = 'static'
    Zone = 1,2
}
#Gateway Internal IP
$gwintip = @{
    Name = 'myintNATgatewayIP'
    ResourceGroupName = $resourcegroup
    Location = $location
    Sku = 'Standard'
    AllocationMethod = 'static'
    Zone = 1,2
}
#Bastion subnet
$bastsubnet = @{
    Name = "AzureBastionSubnet"
    AddressPrefix = "10.1.1.0/24"
}



#Public IP for Bastion
$bastionip = @{
    Name = "myBastionIP"
    ResourceGroupName = $resourcegroup
    Location = $location
    Sku = "Standard"
    AllocationMethod = "Static"
}
#Networksecuritygroup regler for SSH
$nsgruleSSH = @{
    Name                     = 'AllowSSH'
    Description              = 'Allow SSH access'
    Protocol                 = 'TCP'
    SourcePortRange          = '*'
    DestinationPortRange     = '22'
    SourceAddressPrefix      = 'Internet'
    DestinationAddressPrefix = '*'
    Access                   = 'Allow'
    Priority                 = '1000'
    Direction                = 'Inbound'
}

#For at sikre sig man logger ind fra browser, da man ellers ikke kan bruge 2-FA som er påkrævet
Update-AzConfig -EnableLoginByWam $false
#Tilknyt Azure konto
Connect-AzAccount
#Oprettelse af RG
New-AzResourceGroup -Name $resourcegroup -Location $location

#Oprettelse af IP-Adresser
$gwintip = New-AzPublicIpAddress @gwintip
$gwpublicip = New-AzPublicIpAddress @gwpublicip

$natint = @{
    ResourceGroupName = $resourcegroup
    Name = 'NATGatewayint'
    IdleTimeoutInMinutes = "10"
    Sku = "Standard"
    Location = $location
    PublicIpAddress = $gwintip
}
$natpub = @{
    ResourceGroupName    = $resourcegroup
    Name                 = 'NATGatewaypub'
    IdleTimeoutInMinutes = "10"
    Sku                  = "Standard"
    Location             = $location
    PublicIpAddress      = $gwpublicip
}

$natGatewaypub = New-AzNatGateway @natpub
$natGatewayint = New-AzNatGateway @natint
#NSG rule
$nsgrulepub = @{
    Name                     = 'myNSGRuleHTTP'
    Description              = 'Allow HTTP'
    Protocol                 = '*'
    SourcePortRange          = '*'
    DestinationPortRange     = '80'
    SourceAddressPrefix      = 'Internet'
    DestinationAddressPrefix = '*'
    Access                   = 'Allow'
    Priority                 = '2000'
    Direction                = 'Inbound'
}
$rulepub = New-AzNetworkSecurityRuleConfig @nsgrulepub
$ruleSSH = New-AzNetworkSecurityRuleConfig @nsgruleSSH
#NSG - Network Security Group
$nsgpub = New-AzNetworkSecurityGroup `
    -Name "myNSGpub" `
    -ResourceGroupName $resourcegroup `
    -Location $location `
    -SecurityRules $rulepub, $ruleSSH

$nsgint = New-AzNetworkSecurityGroup `
    -Name  'myNSGint' `
    -ResourceGroupName  $resourcegroup `
    -Location  $location `
    -SecurityRules $ruleSSH

 $nsgpub = Get-AzNetworkSecurityGroup `
    -Name "myNSGPub" `
    -ResourceGroupName $resourcegroup


#Subnet
$subnetpub = @{
    Name          = "frontendSubnet"
    AddressPrefix = "10.1.2.0/24"
    NatGateway    = $natGatewaypub
    NetworkSecurityGroup = $nsgpub
}

#Subnet for internal
$subnetint = @{
    Name          = "backendSubnet"
    AddressPrefix = "10.1.0.0/24"
    NatGateway    = $natGatewayint 
    NetworkSecurityGroup = $nsgint 
}
$subnetConfigpub = New-AzVirtualNetworkSubnetConfig @subnetpub
$subnetConfigint = New-AzVirtualNetworkSubnetConfig @subnetint
$bastsubnetConfig = New-AzVirtualNetworkSubnetConfig @bastsubnet

$virtualnet = @{
    Name = "Vnet"
    ResourceGroupName = $resourcegroup
    Location = $location
    AddressPrefix = "10.1.0.0/16"
    Subnet = $subnetConfigpub,$bastsubnetConfig, $subnetConfigint
}

$vnet = New-AzVirtualNetwork @virtualnet

$bastionip = New-AzPublicIpAddress @bastionip

$bastion = @{
    ResourceGroupName = $resourcegroup
    Name = 'myBastion'
    PublicIpAddress = $bastionip
    VirtualNetwork = $vnet
}

New-AzBastion @bastion -AsJob





##############################################################################
#Variabler for brug i LoadBalancer
$vnet = Get-AzVirtualNetwork -Name "Vnet" -ResourceGroupName $resourcegroup
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "backendSubnet" -VirtualNetwork $vnet
######################################################
# Internal Loadbalancer

#Loadbalancer IP
$lbipint = @{
    Name = "internal"
    PrivateIpAddress = "10.1.0.4"
    Subnet = $subnet
}

$lbinternal = @{
    Name = 'InternalLoadBalancer'
    ResourceGroupName = $resourcegroup
}

$feip = New-AzLoadBalancerFrontendIpConfig @lbipint

$bepool = New-AzLoadBalancerBackendAddressPoolConfig -Name "InternalBackEndPool"

$probe = @{
    Name              = "myHealthProbe"
    Protocol          = "tcp"
    Port              = "80"
    IntervalInSeconds = "360"
    ProbeCount        = "5"
}

$probeintern = New-AzLoadBalancerProbeConfig @probe

$lbrule = @{
    Name                    = "myhttprule"
    Protocol                = "tcp"
    FrontendPort            = "80"
    BackendPort             = "80"
    IdleTimeoutInMinutes    = "15"
    FrontendIpConfiguration = $feip
    BackendAddressPool      = $bePool
}
$rule = New-AzLoadBalancerRuleConfig @lbrule -EnableTcpReset

$internalloadbalancer = @{
    ResourceGroupName       = $resourcegroup
    Name                    = "InternalLoadBalancer"
    Location                = $location
    Sku                     = "Standard"
    FrontendIpConfiguration = $feip
    BackendAddressPool      = $bePool
    LoadBalancingRule       = $rule
    Probe                   = $probeintern
}
New-AzLoadBalancer @internalloadbalancer
$bepool = Get-AzLoadBalancer @lbinternal  | Get-AzLoadBalancerBackendAddressPoolConfig

# Set NSG object
$nsgint = Get-AzNetworkSecurityGroup -ResourceGroupName $resourcegroup -Name "myNSGint"

# Credentials 
$adminUsername = "LocalAdmin"
$adminPassword = ConvertTo-SecureString "KeaLocalAdmin1!" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)

# VM Creation Internal Load Balancer
for ($i = 1; $i -le 2; $i++) {
    $vmName = "myVM1$i"

    # Create NIC
    $nic = New-AzNetworkInterface `
        -Name "myNicVM$i" `
        -ResourceGroupName $resourcegroup `
        -Location $location `
        -Subnet $subnet `
        -NetworkSecurityGroup $nsgint `
        -LoadBalancerBackendAddressPool $bepool
    # Configure VM
    $vm_config = New-AzVMConfig `
        -VMName $vmName `
        -VMSize "Standard_D2ds_v4" `
        -SecurityType "Standard" `
        -IdentityType "SystemAssigned"

    # Configure OS settings
    $vm_config = Set-AzVMOperatingSystem `
        -VM $vm_config `
        -ComputerName $vmName `
        -Credential $credential `
        -Linux 

    # Set the source image for the VM
    $vm_config = Set-AzVMSourceImage `
        -VM $vm_config `
        -PublisherName 'Canonical' `
        -Offer '0001-com-ubuntu-server-jammy' `
        -Skus '22_04-lts-gen2' `
        -Version "latest"


    # Attach NIC
    $vm_config = Add-AzVMNetworkInterface `
        -VM $vm_config `
        -Id $nic.Id

    # Set the OS disk (mandatory)
    $vm_config = Set-AzVMOSDisk `
        -VM $vm_config `
        -CreateOption FromImage `
        -StorageAccountType "Standard_LRS"

    # Disable Boot Diagnostics
    $vm_config = Set-AzVMBootDiagnostic -VM $vm_config -Disable

    # Deploy the VM
    New-AzVM `
        -ResourceGroupName $resourcegroup `
        -Location $location `
        -VM $vm_config `
        -GenerateSshKey `
        -SshKeyName "sshkeyvm1$i.pub" 
}
########################################################################################################
#######################################################
$vnet = Get-AzVirtualNetwork -Name "Vnet" -ResourceGroupName $resourcegroup
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "frontendSubnet" -VirtualNetwork $vnet

$lbippub = @{
    Name             = "internal"
    PrivateIpAddress = "10.1.2.4"
    Subnet         = $subnet
}

$lbpublic = @{
    Name              = 'PublicLoadBalancer'
    ResourceGroupName = $resourcegroup
}
# Config for Loadbalancer
$feip = New-AzLoadBalancerFrontendIpConfig @lbippub
$backendPoolPublic = New-AzLoadBalancerBackendAddressPoolConfig -Name "PublicBackendPool"

$probe = @{
    Name              = "PublicHealthProbe"
    Protocol          = "tcp"
    Port              = "80"
    IntervalInSeconds = "360"
    ProbeCount        = "5"
}
$probepublic = New-AzLoadBalancerProbeConfig @probe

$lbrulePublic = @{
    Name                    = "PublicHttpRule"
    Protocol                = "tcp"
    FrontendPort            = "80"
    BackendPort             = "80"
    IdleTimeoutInMinutes    = "15"
    FrontendIpConfiguration = $feip
    BackendAddressPool      = $backendPoolPublic
}

$rule = New-AzLoadBalancerRuleConfig @lbrulePublic -EnableTcpReset 
#Creation of Loadbalancer
$publicLB = @{
    ResourceGroupName       = $resourcegroup
    Name                    = "PublicLoadBalancer"
    Location                = $location
    Sku                     = "Standard"
    FrontendIpConfiguration = $feip
    BackendAddressPool      = $backendPoolPublic
    LoadBalancingRule       = $rule
    Probe                   = $probepublic
}
New-AzLoadBalancer @publicLB
$bepool = Get-AzLoadBalancer @lbpublic  | Get-AzLoadBalancerBackendAddressPoolConfig
$nsgpub = Get-AzNetworkSecurityGroup -ResourceGroupName $resourcegroup -Name "myNSGpub"

## For loop with variable to create virtual machines for load balancer backend pool. ##
for ($i = 1; $i -le 2; $i++) {
    $vmName = "myVM2$i"

    # Create NIC
    $nic = New-AzNetworkInterface `
        -Name "myNicVM2$i" `
        -ResourceGroupName $resourcegroup `
        -Location $location `
        -Subnet $subnet `
        -NetworkSecurityGroup $nsgint `
        -LoadBalancerBackendAddressPool $bepool
    # Configure VM
    $vm_config = New-AzVMConfig `
        -VMName $vmName `
        -VMSize "Standard_D2ds_v4" `
        -SecurityType "Standard" `
        -IdentityType "SystemAssigned"

    # Configure OS settings
    $vm_config = Set-AzVMOperatingSystem `
        -VM $vm_config `
        -ComputerName $vmName `
        -Credential $credential `
        -Linux

    # Set the source image for the VM
    $vm_config = Set-AzVMSourceImage `
        -VM $vm_config `
        -PublisherName 'Canonical' `
        -Offer '0001-com-ubuntu-server-jammy' `
        -Skus '22_04-lts-gen2' `
        -Version "latest"


    # Attach NIC
    $vm_config = Add-AzVMNetworkInterface `
        -VM $vm_config `
        -Id $nic.Id

    # Set the OS disk (mandatory)
    $vm_config = Set-AzVMOSDisk `
        -VM $vm_config `
        -CreateOption FromImage `
        -StorageAccountType "Standard_LRS"

    # Disable Boot Diagnostics
    $vm_config = Set-AzVMBootDiagnostic -VM $vm_config -Disable

    # Deploy the VM
    New-AzVM `
        -ResourceGroupName $resourcegroup `
        -Location $location `
        -VM $vm_config `
        -GenerateSshKey `
        -SshKeyName "sshkeyvm2$i.pub" 
}

######### Azure SQL
$adminUsername = "LocalAdmin"
$adminPassword = ConvertTo-SecureString "Keaadgangskode1!" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
$serverName = "mysqlserver-$(Get-Random)"
$databaseName = "keafinaldb"
$startIp = "10.1.0.40"
$endIp = "10.1.0.50"
$server = New-AzSqlServer -ResourceGroupName $resourcegroup `
      -ServerName $serverName `
      -Location $location `
      -SqlAdministratorCredentials $credential
$server
$serverfirewall = New-AzSqlServerFirewallRule -ResourceGroupName $resourcegroup `
      -ServerName $serverName `
      -FirewallRuleName "AllowedIPs" -StartIpAddress $startIp -EndIpAddress $endIp
$serverfirewall
$serverdb = New-AzSqlDatabase  -ResourceGroupName $resourcegroup `
      -ServerName $serverName `
      -DatabaseName $databaseName `
      -Edition GeneralPurpose `
      -ComputeModel Serverless `
      -ComputeGeneration Gen5 `
      -VCore 2 `
      -MinimumCapacity 2 
$serverdb


#Remove-AzResourceGroup -ResourceGroupName $resourcegroup
