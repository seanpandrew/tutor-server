class Role::AddUserRole
  lev_routine

  protected

  def exec(user:, role:)
    ss_map = Role::Models::User.create(entity_user_id: user.entity_user_id, entity_role_id: role.id)
    transfer_errors_from(ss_map, {type: :verbatim}, true)
  end
end
