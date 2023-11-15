json.seedurl params[:seedurl]
json.latestArtefact @contents.sort_by { |artefact| artefact.last_modified }.last, partial: 'databus/content', as: :content
json.artefacts @contents.sort_by { |artefact| artefact.last_modified }, partial: 'databus/content', as: :content