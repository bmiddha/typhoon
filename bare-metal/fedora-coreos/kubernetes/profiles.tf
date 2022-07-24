locals {
  remote_kernel = "https://builds.coreos.fedoraproject.org/prod/streams/${var.os_stream}/builds/${var.os_version}/${var.os_arch}/fedora-coreos-${var.os_version}-live-kernel-${var.os_arch}"
  remote_initrd = [
    "https://builds.coreos.fedoraproject.org/prod/streams/${var.os_stream}/builds/${var.os_version}/${var.os_arch}/fedora-coreos-${var.os_version}-live-initramfs.${var.os_arch}.img",
    "https://builds.coreos.fedoraproject.org/prod/streams/${var.os_stream}/builds/${var.os_version}/${var.os_arch}/fedora-coreos-${var.os_version}-live-rootfs.${var.os_arch}.img"
  ]

  remote_args = [
    "ip=dhcp",
    "rd.neednet=1",
    "coreos.inst.install_dev=${var.install_disk}",
    "coreos.inst.ignition_url=${var.matchbox_http_endpoint}/ignition?uuid=$${uuid}&mac=$${mac:hexhyp}",
    "coreos.inst.image_url=https://builds.coreos.fedoraproject.org/prod/streams/${var.os_stream}/builds/${var.os_version}/${var.os_arch}/fedora-coreos-${var.os_version}-metal.${var.os_arch}.raw.xz",
    "console=tty0",
    "console=ttyS0",
  ]

  cached_kernel = "/assets/fedora-coreos/fedora-coreos-${var.os_version}-live-kernel-${var.os_arch}"
  cached_initrd = [
    "/assets/fedora-coreos/fedora-coreos-${var.os_version}-live-initramfs.${var.os_arch}.img",
    "/assets/fedora-coreos/fedora-coreos-${var.os_version}-live-rootfs.${var.os_arch}.img"
  ]

  cached_args = [
    "ip=dhcp",
    "rd.neednet=1",
    "coreos.inst.install_dev=${var.install_disk}",
    "coreos.inst.ignition_url=${var.matchbox_http_endpoint}/ignition?uuid=$${uuid}&mac=$${mac:hexhyp}",
    "coreos.inst.image_url=${var.matchbox_http_endpoint}/assets/fedora-coreos/fedora-coreos-${var.os_version}-metal.${var.os_arch}.raw.xz",
    "console=tty0",
    "console=ttyS0",
  ]

  kernel = var.cached_install ? local.cached_kernel : local.remote_kernel
  initrd = var.cached_install ? local.cached_initrd : local.remote_initrd
  args   = var.cached_install ? local.cached_args : local.remote_args
}


// Fedora CoreOS controller profile
resource "matchbox_profile" "controllers" {
  count = length(var.controllers)
  name  = format("%s-controller-%s", var.cluster_name, var.controllers.*.name[count.index])

  kernel = local.kernel
  initrd = local.initrd
  args   = concat(local.args, var.kernel_args)

  raw_ignition = data.ct_config.controller-ignitions.*.rendered[count.index]
}

data "ct_config" "controller-ignitions" {
  count = length(var.controllers)

  content  = data.template_file.controller-configs.*.rendered[count.index]
  strict   = true
  snippets = lookup(var.snippets, var.controllers.*.name[count.index], [])
}

data "template_file" "controller-configs" {
  count = length(var.controllers)

  template = file("${path.module}/fcc/controller.yaml")
  vars = {
    domain_name            = var.controllers.*.domain[count.index]
    etcd_name              = var.controllers.*.name[count.index]
    etcd_initial_cluster   = join(",", formatlist("%s=https://%s:2380", var.controllers.*.name, var.controllers.*.domain))
    cluster_dns_service_ip = module.bootstrap.cluster_dns_service_ip
    cluster_domain_suffix  = var.cluster_domain_suffix
    ssh_authorized_key     = var.ssh_authorized_key
  }
}

// Fedora CoreOS worker profile
resource "matchbox_profile" "workers" {
  count = length(var.workers)
  name  = format("%s-worker-%s", var.cluster_name, var.workers.*.name[count.index])

  kernel = local.kernel
  initrd = local.initrd
  args   = concat(local.args, var.kernel_args)

  raw_ignition = data.ct_config.worker-ignitions.*.rendered[count.index]
}

data "ct_config" "worker-ignitions" {
  count = length(var.workers)

  content  = data.template_file.worker-configs.*.rendered[count.index]
  strict   = true
  snippets = lookup(var.snippets, var.workers.*.name[count.index], [])
}

data "template_file" "worker-configs" {
  count = length(var.workers)

  template = file("${path.module}/fcc/worker.yaml")
  vars = {
    domain_name            = var.workers.*.domain[count.index]
    cluster_dns_service_ip = module.bootstrap.cluster_dns_service_ip
    cluster_domain_suffix  = var.cluster_domain_suffix
    ssh_authorized_key     = var.ssh_authorized_key
    node_labels            = join(",", lookup(var.worker_node_labels, var.workers.*.name[count.index], []))
    node_taints            = join(",", lookup(var.worker_node_taints, var.workers.*.name[count.index], []))
  }
}

