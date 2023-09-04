terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

locals {
  cloud_id  = "b1gnqn31kk61drjvnvj1"
  folder_id = "b1gdl7e67tave2qvj55r"
  subnet_id = "e9buqog943pts89fsr61"
  zone      = "ru-central1-a"

  # ubuntu-20-04-lts-v20220620
  image_id  = "fd8f1tik9a7ap9ik2dg1"
  user      = "ubuntu"

  master_count          = 4
  master_vcpu           = 2
  master_ram            = 8
  master_fraction       = 50
  master_disk_primary   = 30
  # master_disk_secondary = 1024

  master_name_template  = "elastic-%02s"
}

provider "yandex" {
  service_account_key_file = "../keys/yandex/key.json"
  cloud_id  = local.cloud_id
  folder_id = local.folder_id
  zone      = local.zone
}

resource "yandex_vpc_address" "master" {
  count = local.master_count
  name = format(local.master_name_template, count.index + 1)

  external_ipv4_address {
    zone_id = local.zone
  }
}

# resource "yandex_compute_disk" "master" {
#   name = format("k1s-master-disk-%02s", count.index + 1)

#   count = local.master_count

#   type = "network-hdd"
#   zone = local.zone
#   size = local.master_disk_secondary
# }

resource "yandex_compute_instance" "master" {
  name = format(local.master_name_template, count.index + 1)
  platform_id = "standard-v3"   # Ice Lake, allows 20, 50 or 100 core fraction

  count = local.master_count
  
  resources {
    cores  = local.master_vcpu
    memory = local.master_ram
    core_fraction = local.master_fraction
  }

  boot_disk {
    initialize_params {
      image_id = local.image_id
      size = local.master_disk_primary
    }
  }

  # secondary_disk {
  #   disk_id = yandex_compute_disk.master[count.index * 3].id
  # }

  # secondary_disk {
  #   disk_id = yandex_compute_disk.master[count.index * 3 + 1].id
  # }

  # secondary_disk {
  #   disk_id = yandex_compute_disk.master[count.index * 3 + 2].id
  # }

  network_interface {
    subnet_id       = local.subnet_id
    nat             = true
    nat_ip_address  = yandex_vpc_address.master[count.index].external_ipv4_address[0].address
  }

  metadata = {
    ssh-keys = "${local.user}:${file("../keys/ssh/id_rsa.pub")}"
  }
}

data "template_file" "inventory" {
  template = "${file("templates/inventory.tpl")}"
  
  vars = {
    user = local.user
    hosts-master = "${join("\n", [for instance in yandex_compute_instance.master : join("", [instance.name, " ansible_host=", instance.network_interface.0.nat_ip_address, " internal_ip=", instance.network_interface.0.ip_address, " external_ip=", instance.network_interface.0.nat_ip_address])] )}"
  }
}

resource "local_file" "save_inventory" {
  content  = data.template_file.inventory.rendered
  filename = "../inventory"
}