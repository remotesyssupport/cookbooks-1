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

template "/etc/ceph/ceph.conf" do
  source "ceph.conf.erb"
  variables(
    :mon => search(:node, 'recipes:ceph\:\:mon'),
    :mds => search(:node, 'recipes:ceph\:\:mds'),
    :osd => search(:node, 'recipes:ceph\:\:osd')
  )
  notifies :run, "execute[restart mon service]"
end

execute "restart mon service" do                                                                                                                                             
  action :nothing                                                                                                                                                            
  # needs good condition                                                                                                                                                     
  only_if { false }                                                                                                                                                          
  command "/etc/init.d/ceph restart mon"                                                                                                                                     
end 

service "ceph" do
  supports :restart => true
end
