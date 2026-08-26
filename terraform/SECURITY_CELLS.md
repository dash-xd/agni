# Security cell placement contract

Agni is the host/network substrate for regional security cells. A cell may use the existing Agni VPC, regional subnet, Fedora CoreOS member placement, leader ingress, and Squid egress while higher-level tenant/IAM policy remains outside Agni.

`huram-abi-master` owns the security-cell manifest and deployment policy. Atman owns identity-based tenant routing. marai remains one process per cryptographic isolation domain. Logma owns event distribution.

Agni metadata and CoreOS bootstrap should remain generic: role, leader IP, subnet CIDR, service port, Redis DB slot, and other host-level placement data may be supplied by Terraform, while tenant registries, ACL credentials, KMS keys, and secret/event policy are runtime concerns.

The preferred production default is one isolated cell per tenant. `shared-host` may place several tenant runtimes on one CoreOS member, but each tenant must retain a separate marai process, Unix socket, ACL credential set, and writable `/run` subtree. Sharing one marai process across tenants is intentionally unsupported.
