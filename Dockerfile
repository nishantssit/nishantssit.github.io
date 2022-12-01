#FROM public.ecr.aws/lambda/dotnet:5.0
#
#WORKDIR /var/task
#
## This COPY command copies the .NET Lambda project's build artifacts from the host machine into the image. 
## The source of the COPY should match where the .NET Lambda project publishes its build artifacts. If the Lambda function is being built 
## with the AWS .NET Lambda Tooling, the `--docker-host-build-output-dir` switch controls where the .NET Lambda project
## will be built. The .NET Lambda project templates default to having `--docker-host-build-output-dir`
## set in the aws-lambda-tools-defaults.json file to "bin/Release/net5.0/linux-x64/publish".
##
## Alternatively Docker multi-stage build could be used to build the .NET Lambda project inside the image.
## For more information on this approach checkout the project's README.md file.
#COPY "bin/Release/net5.0/linux-x64/publish"  .

# Official microsoft .NET SDK image
FROM mcr.microsoft.com/dotnet/sdk:5.0-alpine AS api-build

# Set directory for build
# for better working with environment variables and lambda conform should be in /var/task
WORKDIR /var/task

# Copy anything from where docker would be builded
COPY src ./

# Copy RIE
#COPY bin ./bin

# Recieve packages, Build and shrink as an standalone executable file
#RUN rm -rf obj bin

# Setup custom dotnet env variables
# See here for more info: https://github.com/dotnet/docs/blob/master/docs/core/tools/dotnet.md
ENV \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    # Lambda is optionated about installing tooling under /var
    DOTNET_ROOT=/var/lang/dotnet \
    # Don't display welcome message on first run
    DOTNET_NOLOGO=true \
    # Disable Microsoft's telemetry collection
    DOTNET_CLI_TELEMETRY_OPTOUT=true


RUN dotnet publish -c Release -r linux-musl-x64 \
   /p:AWSProjectType="Lambda" \
   /p:LangVersion="latest" \
   /p:TargetFramework="net5.0" \
   /p:AssemblyName="bootstrap" \
   /p:RuntimeIdentifier="linux-musl-x64" \
   /p:PublishSingleFile="true" \
   /p:PublishReadyToRun="true" \
   /p:GenerateDocumentationFile="false" \
   /p:ExecutableOutputType="true" \
   /p:OutputType="Exe" \
   /p:CopyLocalLockFileAssemblies="true" \
   /p:PublishTrimmed="true" \
   /p:Optimize="true" \
   /p:TrimMode="link" \
   /p:TieredCompilationQuickJit="false" \
   /p:TieredCompilation="false" \
   /p:CopyLocalLockFileAssemblies="true" \
   /p:SuppressTrimAnalysisWarnings="true" \
  --self-contained true \
  -o release

# Set very small linux distribution as an base for a service
FROM alpine:latest AS runtime

# Set environment from arguments or let default
ARG DEFAULT_ENV
ENV STAGE_ENVIRONMENT=$DEFAULT_ENV

# https://github.com/aws/aws-lambda-dotnet/blob/master/LambdaRuntimeDockerfiles/dotnet5/Dockerfile
ENV \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    # Lambda is opinionated about installing tooling under /var
    DOTNET_ROOT=/var/lang/bin \
    # Don't display welcome message on first run
    DOTNET_NOLOGO=true \
    # Disable Microsoft's telemetry collection
    DOTNET_CLI_TELEMETRY_OPTOUT=true \
    # The AWS base images provide the following environment variables:
    LAMBDA_TASK_ROOT=/var/task \
    LAMBDA_RUNTIME_DIR=/var/runtime \
    # https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html?icmpid=docs_lambda_console
    # For the .NET 3.1 runtime, set this variable to enable or disable .NET 3.1 specific runtime optimizations.
    # Values include "always", "never", and "provisioned-concurrency".
    # For information, see Configuring provisioned concurrency.
    AWS_LAMBDA_DOTNET_PREJIT="Always"
    # https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html?icmpid=docs_lambda_console
    #AWS_LAMBDA_INITIALIZATION_TYPE="provisioned-concurrency"

# Allow to redirect and get work .NET web service from any host
# But needs to open(dispose) ports by run docker
#ENV ASPNETCORE_URLS=http://+:8080

# Expose HTTP port
#EXPOSE 8080

#ENV PATH=/var/lang/bin:/usr/local/bin:/usr/bin/:/bin:/opt/bin
#ENV LD_LIBRARY_PATH=/var/lang/lib:/lib64:/usr/lib64:/var/runtime:/var/runtime/lib:/var/task:/var/task/lib:/opt/lib
#ENV LAMBDA_TASK_ROOT=/var/task
#ENV LAMBDA_RUNTIME_DIR=/var/runtime

# Install dependencies
# https://docs.microsoft.com/en-us/dotnet/core/install/linux-alpine
# --no-cache option allows to not cache the index locally, which is useful for keeping containers small
# Literally it equals `apk update` in the beginning and `rm -rf /var/cache/apk/*` in the end.
RUN apk add --no-cache musl icu-libs krb5-libs

# Set directory to run from
WORKDIR /var/task

# Copy executable
COPY --from=api-build /var/task/release/bootstrap* ./
#COPY --from=api-build /var/task/bin/entry.sh ./
#COPY --from=api-build /var/task/bin/aws-lambda-rie /usr/bin/aws-lambda-rie
#COPY --from=api-build /var/task/bin/entry.sh /var/task

# (Optional) Add Lambda Runtime Interface Emulator and use a script in the ENTRYPOINT for simpler local runs
#ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie /usr/bin/aws-lambda-rie
#COPY entry.sh /
#RUN chmod 755 /usr/bin/aws-lambda-rie /entry.sh

#https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html#configuration-envvars-runtime
#aws-proxy(bootsrap)

ENTRYPOINT ["/var/task/bootstrap"]

# Default entry point executrable
#CMD ["/var/task/bootstrap"]

## This is the place where you define the function handler to not explicitly have to do it.
## Check "Testing container image Lambda functions" Part in 
## https://aws.amazon.com/de/blogs/developer/net-5-aws-lambda-support-with-container-images/
## Structure should be like "Assembly::Namespace.ClassName::MethodName"
#CMD ["geoinformation::geoinformation.Function::FunctionHandler"]
