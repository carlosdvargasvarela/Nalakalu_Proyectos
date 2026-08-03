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
    valid_rows = JSON.parse(params[:valid_rows] || "[]")
    @results = commit_rows(@project_type, valid_rows)
    render :new
  end

  private

  def commit_rows(project_type, valid_rows)
    created = 0
    row_errors = []

    valid_rows.each_with_index do |row, index|
      project = Project.new(project_type: project_type, name: row["name"], custom_fields: row["custom_fields"])
      if project.save
        ProjectAccess.create!(user: current_user, project: project, can_edit: true) if current_user.gerente?
        created += 1
      else
        row_errors << { row: index + 2, message: project.errors.full_messages.join(", ") }
      end
    end

    { created: created, errors: row_errors }
  end

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end

  def build_preview(project_type, file)
    return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "No se subió ningún archivo" }], valid_rows_json: "[]" } if file.blank?

    fields = project_type.field_definitions.order(:position).to_a
    parsed_rows = begin
      parse_rows(file, fields)
    rescue ArgumentError
      return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "Formato no soportado, subí un .csv, .xlsx o .xls" }], valid_rows_json: "[]" }
    end
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
    when ".xlsx", ".xls"
      sheet = Roo::Spreadsheet.open(file.path, extension: extension.delete(".").to_sym).sheet(0)
      header = sheet.row(1)
      (2..sheet.last_row).map do |i|
        row = header.zip(sheet.row(i)).to_h
        [row["Nombre"], fields.each_with_object({}) { |f, h| h[f.key] = resolve_field_value(f, row[f.label]) }]
      end
    else
      raise ArgumentError, "unsupported extension"
    end
  end

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank? || field.data_type != "reference"

    record = field.reference_table.classify.constantize.find_by(name: raw_value.strip)
    record ? record.id : "#{raw_value} (no encontrado)"
  end
end
