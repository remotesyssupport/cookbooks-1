require 'base64'

a = false
search(:node, 'recipes:ceph\:\:mds').each { |mds| a = true if mds[:hostname] == node[:hostname] }
if a
  include_recipe "ceph"
  directory "/tmp/ceph-stage2"

  template "/tmp/ceph-stage2/conf" do
    source "ceph.conf.erb"
    variables(
      :mon => search(:node, 'recipes:ceph\:\:mon'),
      :osd => search(:node, 'recipes:ceph\:\:osd'),
      :mds => search(:node, 'recipes:ceph\:\:mds')
    )
  end

  file "/tmp/ceph-stage2/monmap" do
    content Base64.decode64(search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap])
  end

  execute "init mds" do
    command "mkcephfs -c /etc/ceph/ceph.conf -d /tmp/ceph-stage2 --init-local-daemons mds"
    not_if { File.exists?("/tmp/ceph-stage2/key.mds.*") }
  end

  ruby_block "read key && keyring" do
    block do
      key = Base64.encode64(File.read("/tmp/ceph-stage2/key.mds.#{node[:hostname]}"))
      node.set[:ceph][:mds][:key] = key
      keyring = Base64.encode64(File.read("/tmp/ceph-stage2/keyring.mds.#{node[:hostname]}"))
      node.set[:ceph][:mds][:keyring] = keyring
    end
    not_if { node[:ceph][:mds] }
  end
end

