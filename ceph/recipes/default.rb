#
# Cookbook Name:: ceph
# Recipe:: default
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
execute "add chef repo key" do
  command "wget -q -O- https://raw.github.com/NewDreamNetwork/ceph/master/keys/release.asc | apt-key add -"
  not_if { IO.popen("apt-key list").read.include?("1024D/288995C8") }
end

case node[:platform]
when "ubuntu"
  distro = node[:lsb][:codename]
when "debian"
  distro = IO.popen("lsb_release -cs").read.chomp
end

template "/etc/apt/sources.list.d/ceph.list" do
  source "ceph.list.erb"
  variables :distro => distro
  notifies :run, "execute[apt-get update]", :immediately
end

execute "apt-get update" do
  action :nothing
  command "apt-get update"
end

package "ceph"
