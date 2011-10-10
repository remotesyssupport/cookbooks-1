require 'base64'

include_recipe "ceph"

# this recipe should mount cluster and create directory for each app server (only if there are at least 2 osds active)
if IO.popen("ceph -s").read.match(/(\d) osds/)[1].to_i >= 2

  directory "/mnt/cluster"

  execute "mount /mnt/cluster" do
    command "ceph-fuse -m #{search(:node, 'recipes:ceph\:\:mon').first["ipaddress"]}:/ /mnt/cluster"
    not_if { IO.popen("mount").read.include?("/mnt/cluster") }
  end

  if IO.popen("mount").read.include?("/mnt/cluster")
    search(:node, 'recipes:application_server').each do |app|
      directory "/mnt/cluster/#{app[:hostname]}"
    end
  end

end
