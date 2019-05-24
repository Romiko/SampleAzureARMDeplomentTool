# uma-infrastructure
Deploy Cloud Infrastructure

# Configuration
Add environment configuration to EnvironmentDeployment.json

# Deploy
Run a deployment with the configuration
  ## Deploy all resources defined
  This will deploy all resources in the umqa section defined in EnvironmentDeployment.json
  ```
  ./EnvironmentDeployment.ps1 -configFile .\EnvironmentDeployment.json -environment umqa -baseDir C:\Code
   ```
  ## Deploy only resources defined with VirtualMachines Tag
  This will deploy only resources tagged with VirtualMachines in the umqa section defined in EnvironmentDeployment.json
  ```
  ./EnvironmentDeployment.ps1 -configFile .\EnvironmentDeployment.json -environment umqa -baseDir C:\Code -resources VirtualMachines
  ```

# Resources
Leverage resource tags is a great way to deploy a subset of resources in an environment e.g. Only SQL Servers, Virtual Machines. Great to focus on just deploying items in a resourceGroup.

# Naming Convention
This deployment structure relies heavily on a solid naming convention standard being enforced.
Environment Prefix - max 4 characters - productCode + enviroment e.g. umqa (qa), umpr (prod), umde (dev), umua (uat).

Azure has various name length limits as well. Keeping our prefix codes short ensures we are within the limit.

Having a solid naming convention also allows for a coventional approach to confgiruation management by managing resources by classification e.g. regex
