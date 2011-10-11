module Ceph

  # checks if osd is fully configured, it works only at initial cluster node
  def osd_fullyconfigured?
    search(:node, 'recipes:ceph\:\:osd').any? { |osd| osd[:ceph][:osd] && osd[:ceph][:osd][:key] && osd[:ceph][:osd][:keyring] }
  end

  # checks if mds is fully configured, it works only at initial cluster node
  def mds_fullyconfigured?
    search(:node, 'recipes:ceph\:\:mds').any? { |mds| mds[:ceph][:mds] && mds[:ceph][:mds][:key] && mds[:ceph][:mds][:keyring] }
  end

  # functions checks if there is at least node with ceph::mon recipe completed
  def cluster_exists?
    not (search(:node, 'recipes:ceph\:\:mon').empty?)
  end

  # function returns proper string with all mons for chef-fuse 
  def get_monitors
    if cluster_exists?
      return search(:node, 'recipes:ceph\:\:mon').map { |m| m["ipaddress"] }.join(",")
    else
      nil
    end
  end
end
