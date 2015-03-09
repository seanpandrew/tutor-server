class CourseMembership::GetTeachers
  lev_routine

  protected

  def exec(course)
    ss_maps = CourseMembership::Teacher.where{entity_course_id == course.id}
    outputs[:teachers] = ss_maps.collect{|ss_map| ss_map.entity_role}
  end
end
