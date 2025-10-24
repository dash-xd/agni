# Minimal static repo server using BusyBox HTTPD
FROM quay.io/fedora/fedora-minimal:latest
RUN microdnf install -y busybox && microdnf clean all

WORKDIR /srv
COPY builds/latest/x86_64/repo /srv/repo

EXPOSE 8080
CMD ["busybox", "httpd", "-f", "-p", "8080", "-h", "/srv/repo"]
