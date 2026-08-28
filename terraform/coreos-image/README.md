# Agni CoreOS GCP image publisher

This directory is a Terraform **root module intended to be executed by the separate deployment repository**, not by a workflow in `dash-xd/agni`.

The deployment workflow should:

1. check out a pinned Agni commit;
2. run `qemu/coreos-live/production/build.sh all` on a runner with KVM;
3. upload the generated `*-gcp.*.tar.gz` artifact to GCS;
4. optionally archive the sibling live ISO to GCS for reproducibility/local installation;
5. initialize this Terraform root with the deployment repository's GCS backend configuration;
6. apply with an immutable `image_name` based on the Agni source commit;
7. consume the stable `agni-coreos` image family from the instance-template layer.

Example:

```sh
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="prefix=terraform/agni-coreos-image"

terraform apply -auto-approve \
  -var="project_id=${GCP_PROJECT_ID}" \
  -var="staging_bucket_name=${COREOS_IMAGE_BUCKET}" \
  -var="image_object=images/${AGNI_SHA}/agni-coreos-gcp.x86_64.tar.gz" \
  -var="image_name=agni-coreos-${AGNI_SHA:0:12}"
```

The module does not upload local files. GCS upload is deliberately owned by the external workflow so Terraform state tracks the cloud image resource rather than large local build artifacts.

The resulting image family can be consumed by another Terraform layer:

```hcl
data "google_compute_image" "agni_coreos" {
  project = var.project_id
  family  = "agni-coreos"
}
```

Then use `data.google_compute_image.agni_coreos.self_link` as the boot image for the instance template. Agni's existing member deployment can continue using `google_compute_instance_from_template`; only the template-producing layer needs to move from the stock FCOS image to this family.
