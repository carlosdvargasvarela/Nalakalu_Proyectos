require "csv"

class ImportsController < ApplicationController
  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    project_type = ProjectType.find(params[:project_type_id])
    send_data csv_template_for(project_type), filename: "plantilla-#{project_type.slug}.csv", type: "text/csv"
  end

  def create
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @results = import_rows(@project_type, params[:file])
    render :new
  end

  private

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end

  def import_rows(project_type, file)
    return { created: 0, errors: [{ row: 0, message: "No se subió ningún archivo" }] } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    rows = CSV.parse(file.read.force_encoding("UTF-8").sub("﻿", ""), headers: true)
    created = 0
    row_errors = []

    rows.each_with_index do |row, index|
      custom_fields = fields.each_with_object({}) do |field, hash|
        hash[field.key] = resolve_field_value(field, row[field.label])
      end
      project = Project.new(project_type: project_type, name: row["Nombre"], custom_fields: custom_fields)
      if project.save
        created += 1
      else
        row_errors << { row: index + 2, message: project.errors.full_messages.join(", ") }
      end
    end

    { created: created, errors: row_errors }
  end

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank? || field.data_type != "reference"

    record = field.reference_table.classify.constantize.find_by(name: raw_value.strip)
    record ? record.id : "#{raw_value} (no encontrado)"
  end
end
