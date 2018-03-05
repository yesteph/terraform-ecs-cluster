#!groovy

def mailto = "egirondel.prestataire@oui.sncf, steyssier.prestataire@oui.sncf"
def gitlabBaseURL = "http://gitlab.socrate.vsct.fr/terraformcentral/"
def gitRepositoryName
def gitRepositoryURL
def gitRepositoryCommit
def gitCommitID
def gitCommitter

stage("Checkout") {
    node("gitsocrate") {
        deleteDir()
        // Checkout
        checkout scm
        // Get Git informations
        gitRepositoryName = sh(script: "git config --get remote.origin.url|sed -E \"s/^.*\\/(.*)\\.git\$/\\1/\"", returnStdout: true).trim()
        gitCommitID = sh(script: "git log -n 1 --format=%H", returnStdout: true).trim()
        gitCommitter = sh(script: "git log -n 1 --format=%ce", returnStdout: true).trim()
        gitRepositoryURL = "${gitlabBaseURL}${gitRepositoryName}"
        gitRepositoryCommit = "${gitlabBaseURL}${gitRepositoryName}/commit/${gitCommitID}"
        stash name: 'source', useDefaultExcludes: false
    }
}

stage("Check formatting") {
    node("amazon") {
        deleteDir()
        unstash 'source'

        ansiColor("xterm") {
            try {
                // This check will fail if any terraform file isn't properly formatted
                sh(script: "terraform fmt -check=true -list=true")
            } catch (Exception e) {
                // Send mail to commiter
                mail to: "${gitCommitter}",
                        subject: "[AWS][Terraform] Last commit to ${gitRepositoryName} failed validations",
                        body: "Hello,\n\nYour last push to master with git commit ${gitCommitID} on ${gitRepositoryName} failed validations and can't be tagged.\n\nGitlab Repository: ${gitRepositoryURL}\nGitlab Commit: ${gitRepositoryCommit}\nJenkins run: ${env.BUILD_URL}"
                throw e
            }
        }
    }
}

// Everything is fine, ready to tag
stage("Tag module") {
    // Send validation mail
    mail to:"${mailto}",
            subject: "[AWS][Terraform] New version of ${gitRepositoryName} is ready to be tagged",
            body: "Hello fellows,\n\nLast push to master with git commit ${gitCommitID} from ${gitCommitter} on ${gitRepositoryName} was successfully checked and can be tagged through this Jenkins job: ${env.JOB_URL} with the following build ID : ${env.BUILD_DISPLAY_NAME}.\n\nGitlab Repository: ${gitRepositoryURL}\nGitlab Commit: ${gitRepositoryCommit}\nJenkins run: ${env.BUILD_URL}"

    // Ask for module tag
    def responseValues = input(
            message: "Tag module ?",
            parameters: [
                    string(description: 'Module tag to use', name: 'releaseTag')
            ],
            submitterParameter: "submitter",
            ok: 'Tag the module'
    )
    def releaseTag = responseValues['releaseTag']
    def approbator = responseValues['submitter']

    echo "Module will be tagged with tag ${releaseTag}, approved by ${approbator}"

    // Tag module on gitlab
    node("gitsocrate") {
        deleteDir()
        unstash 'source'

        sshagent(['git-credentials']) {
            sh """
				git tag -a "${releaseTag}" -m "Release ${releaseTag} \$(date +'%Y/%m/%d')"
				git push --tags
			"""
        }
    }

    // Send tag mail
    mail to:"${mailto}",
            subject: "[AWS][Terraform] ${gitRepositoryName} tagged as ${releaseTag}",
            body: "Hello fellows,\n\n${gitRepositoryName} was tagged as ${releaseTag}, approved by ${approbator}.\n\nGitlab Repository: ${gitlabBaseURL}${gitRepositoryName}\nGitlab Commit: ${gitlabBaseURL}${gitRepositoryName}/commit/${gitCommitID}\nJenkins run: ${env.BUILD_URL}"
}