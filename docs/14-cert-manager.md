# cert-manager

Deploys CRDs and LAB issuers:

- lab-selfsigned
- lab-ca-issuer

Certificate CNs use DNS names (`lab-ca.lab.example`), never IPs.

Replace LAB CA with production PKI before production use.
