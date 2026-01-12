apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: petpulse-ingress
  annotations:
    kubernetes.io/ingress.global-static-ip-name: "{{STATIC_IP_NAME}}"
    ingress.gcp.kubernetes.io/pre-shared-cert: "{{MANAGED_CERT_NAME}}"
    networking.gke.io/v1beta1.FrontendConfig: "ssl-redirect"
spec:
  rules:
  - host: "{{DOMAIN_NAME}}"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: petpulse-network
            port:
              number: 80
