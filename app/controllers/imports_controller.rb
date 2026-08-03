require "csv"
require "roo"

class ImportsController < ApplicationController
  before_action :require_admin_or_gerente!

  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    project_type = ProjectType.find(params[:project_type_id])
    send_data csv_template_for(project_type), filename: "plantilla-#{project_type.slug}.csv", type: "text/csv"
  end

  def preview
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @preview = build_preview(@project_type, params[:file])
    render :new
  end

  def create
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @results = { created: 0, errors: [] }
    render :new
  end

  private

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end

  def build_preview(project_type, file)
    return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "No se subió ningún archivo" }], valid_rows_json: "[]" } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    parsed_rows = parse_rows(file, fields)
    rows = []
    valid_rows = []

    parsed_rows.each_with_index do |(name, custom_fields), index|
      project = Project.new(project_type: project_type, name: name, custom_fields: custom_fields)
      if project.valid?
        rows << { row: index + 2, name: name, custom_fields: custom_fields, error: nil }
        valid_rows << { name: name, custom_fields: custom_fields }
      else
        rows << { row: index + 2, name: name, custom_fields: custom_fields, error: project.errors.full_messages.join(", ") }
      end
    end

    { rows: rows, valid_rows_json: valid_rows.to_json }
  end

  def parse_rows(file, fields)
    extension = File.extname(file.original_filename).downcase

    case extension
    when ".csv"
      CSV.parse(file.read.force_encoding("UTF-8").sub("﻿", ""), headers: true).map do |row|
        [row["Nombre"], fields.each_with_object({}) { |f, h| h[f.key] = resolve_field_value(f, row[f.label]) }]
      end
    else
      raise NotImplementedError, "xlsx/xls support added in a later task"
    end
  end

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank? || field.data_type != "reference"

    record = field.reference_table.classify.constantize.find_by(name: raw_value.strip)
    record ? record.id : "#{raw_value} (no encontrado)"
  end
end
