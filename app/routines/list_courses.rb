class ListCourses
  lev_routine

  uses_routine UserIsCourseStudent,
               translations: { outputs: { type: :verbatim } },
               as: :is_student
  uses_routine UserIsCourseTeacher,
               translations: { outputs: { type: :verbatim } },
               as: :is_teacher
  uses_routine GetTeacherNames,
               translations: { outputs: { type: :verbatim } },
               as: :get_teacher_names
  uses_routine GetUserCourseRoles,
               translations: { outputs: { type: :verbatim } },
               as: :get_course_roles

  protected

  def exec(user: nil, with: [])
    outputs[:courses] = collect_course_information(user)
    run_with_options(user, with)
  end

  private
  def collect_course_information(user)
    profiles = if user
                 CourseProfile::Models::Profile.all.select do |p|
                   run(:is_student, user: user, course: p.course)
                       .outputs.user_is_course_student ||
                   run(:is_teacher, user: user, course: p.course)
                       .outputs.user_is_course_teacher
                 end
               else
                 CourseProfile::Models::Profile.all
               end
    profiles.collect do |p|
      {
        id: p.entity_course_id,
        name: p.name
      }
    end
  end

  def run_with_options(user, with)
    [with].flatten.each do |option|
      case option
      when :teacher_names
        set_teacher_names_on_courses
      when :roles
        set_roles_on_courses(user)
      end
    end
  end

  def set_teacher_names_on_courses
    outputs.courses.each do |course|
      routine = run(:get_teacher_names, course.id)
      course.teacher_names = routine.outputs.teacher_names
    end
  end

  def set_roles_on_courses(user)
    outputs.courses.each do |course|
      roles = get_roles(course, user)
      course.roles = roles.collect do |role|
        { id: role.id, type: role.role_type }
      end
    end
  end

  def get_roles(course, user)
    entity_course = Entity::Course.find(course.id)
    run(:get_course_roles, course: entity_course, user: user).outputs.roles
  end

end
