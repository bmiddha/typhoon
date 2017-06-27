# Managed Instance Group
resource "google_compute_instance_group_manager" "workers" {
  name        = "${var.cluster_name}-worker-group"
  description = "Compute instance group of ${var.cluster_name} workers"

  # Instance name prefix for instances in the group
  base_instance_name = "${var.cluster_name}-worker"
  instance_template  = "${google_compute_instance_template.worker.self_link}"
  update_strategy    = "RESTART"
  zone               = "${var.zone}"
  target_size        = "${var.count}"

  # Target pool instances in the group should be added into
  target_pools = [
    "${google_compute_target_pool.workers.self_link}",
  ]
}

# bootkube-worker Container Linux config
data "template_file" "worker_config" {
  template = "${file("${path.module}/cl/bootkube-worker.yaml.tmpl")}"

  vars = {
    k8s_dns_service_ip      = "${cidrhost(var.service_cidr, 10)}"
    k8s_etcd_service_ip     = "${cidrhost(var.service_cidr, 15)}"
    ssh_authorized_key      = "${var.ssh_authorized_key}"
    kubeconfig_ca_cert      = "${var.kubeconfig_ca_cert}"
    kubeconfig_kubelet_cert = "${var.kubeconfig_kubelet_cert}"
    kubeconfig_kubelet_key  = "${var.kubeconfig_kubelet_key}"
    kubeconfig_server       = "${var.kubeconfig_server}"
  }
}

data "ct_config" "worker_ign" {
  content      = "${data.template_file.worker_config.rendered}"
  pretty_print = false
}

resource "google_compute_instance_template" "worker" {
  name_prefix  = "${var.cluster_name}-worker-"
  description  = "bootkube-worker Instance template"
  machine_type = "${var.machine_type}"

  metadata {
    user-data = "${data.ct_config.worker_ign.rendered}"
  }

  scheduling {
    automatic_restart = "${var.preemptible ? false : true}"
    preemptible       = "${var.preemptible}"
  }

  # QUIRK: Undocumented field defaults to true if not set
  automatic_restart = "${var.preemptible ? false : true}"

  disk {
    auto_delete  = true
    boot         = true
    source_image = "${var.os_image}"
    disk_size_gb = "${var.disk_size}"
  }

  network_interface {
    network = "${var.network}"

    # Ephemeral external IP
    access_config = {}
  }

  can_ip_forward = true

  service_account {
    scopes = [
      "storage-ro",
      "compute-rw",
      "datastore",
      "userinfo-email",
    ]
  }

  tags = ["worker"]

  lifecycle {
    # To update an Instance Template, Terraform should replace the existing resource
    create_before_destroy = true
  }
}
